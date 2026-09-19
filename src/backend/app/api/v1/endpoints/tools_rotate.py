import json
import logging
import os
import shutil
import tempfile
from pathlib import Path
from typing import Optional

import fitz  # PyMuPDF
from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.services.pdf_rotate_service import rotate_pdf_pages
from app.services.file_staging_service import FileStagingService

router = APIRouter()
logger = logging.getLogger(__name__)

CONFIG_PATH = Path(__file__).parent.parent.parent / "app_limits_config.json"
DEFAULT_MAX_FILE_BYTES = 100 * 1024 * 1024  # 100MB


def get_max_file_bytes() -> int:
    """Reads base limit from app_limits_config.json or falls back to 100MB."""
    try:
        if CONFIG_PATH.exists():
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                mb = data.get("base_max_file_mb", 100)
                return int(mb * 1024 * 1024)
    except Exception as e:
        logger.warning("Could not read app_limits_config.json: %s", e)
    return DEFAULT_MAX_FILE_BYTES


def cleanup_directory(path: str) -> None:
    """Removes temporary working directory and intermediate rotated files."""
    try:
        if os.path.exists(path):
            shutil.rmtree(path, ignore_errors=True)
            logger.info("Purged temporary rotate directory: %s", path)
    except Exception as e:
        logger.warning("Failed to purge temp directory %s: %s", path, e)


@router.post("/rotate")
async def rotate_pdf_endpoint(
    background_tasks: BackgroundTasks,
    file: Optional[UploadFile] = File(None),
    session_file_id: Optional[str] = Form(None),
    rotations: Optional[str] = Form(None),
    rotations_json: Optional[str] = Form(None),
):
    """
    Applies angle rotations to specified pages of an uploaded or staged PDF document.
    Executes locally in temporary storage with PyMuPDF.

    Parameters:
    - file: Uploaded PDF file stream (optional if session_file_id is provided)
    - session_file_id: Token of previously staged file in RAM cache (skips re-uploading)
    - rotations / rotations_json: JSON string mapping page index to angle,
      e.g. '{"0": 90, "1": 180}'
    """
    contents: Optional[bytes] = None
    filename: str = "document.pdf"

    if session_file_id:
        staged = FileStagingService.get_staged_file(session_file_id)
        if staged:
            contents, filename = staged
        elif file is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Staged session file expired or not found. Please upload again.",
            )

    if contents is None and file is not None:
        filename = (file.filename or "document.pdf").strip()
        if not filename.lower().endswith(".pdf"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Only PDF files are supported.",
            )
        contents = await file.read()

    if contents is None or len(contents) == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No PDF file or valid session_file_id provided.",
        )

    max_bytes = get_max_file_bytes()
    if len(contents) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File exceeds maximum allowed size of {max_bytes // (1024 * 1024)}MB.",
        )

    # Create temporary working directory
    temp_dir = Path(tempfile.mkdtemp(prefix="freepdftoolz_rotate_"))
    background_tasks.add_task(cleanup_directory, str(temp_dir))

    temp_input_path = temp_dir / "input.pdf"
    temp_output_path = temp_dir / f"{Path(filename).stem}_rotated.pdf"

    try:
        temp_input_path.write_bytes(contents)

        # Parse rotation instructions
        raw_rotations = rotations or rotations_json or "{}"
        try:
            parsed_rotations = json.loads(raw_rotations)
            if not isinstance(parsed_rotations, dict):
                raise ValueError("Rotations payload must be a JSON object mapping page numbers to angles.")
            rotation_map = {int(k): int(v) for k, v in parsed_rotations.items()}
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Invalid rotations specification: {str(exc)}",
            )

        # Execute rotation
        try:
            rotate_pdf_pages(temp_input_path, temp_output_path, rotation_map)
        except ValueError as val_err:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=str(val_err),
            )
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Failed to process PDF: {str(exc)}",
            )

        if not temp_output_path.exists():
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Rotated PDF was not successfully generated.",
            )

        return FileResponse(
            path=str(temp_output_path),
            media_type="application/pdf",
            filename=temp_output_path.name,
            background=background_tasks,
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Unexpected error rotating PDF: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An error occurred while rotating the PDF: {str(e)}",
        )
