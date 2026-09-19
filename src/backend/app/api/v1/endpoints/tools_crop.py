import json
import logging
import os
import shutil
import tempfile
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.services.pdf_crop_service import crop_pdf
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
    """Removes temporary working directory and intermediate cropped files."""
    try:
        if os.path.exists(path):
            shutil.rmtree(path, ignore_errors=True)
            logger.info("Purged temporary crop directory: %s", path)
    except Exception as e:
        logger.warning("Failed to purge temp directory %s: %s", path, e)


@router.post("/crop")
async def crop_pdf_endpoint(
    background_tasks: BackgroundTasks,
    file: Optional[UploadFile] = File(None),
    session_file_id: Optional[str] = Form(None),
    left: float = Form(0.0),
    top: float = Form(0.0),
    right: float = Form(0.0),
    bottom: float = Form(0.0),
    apply_to_all: bool = Form(True),
    target_page: int = Form(0),
):
    """
    Applies margin cropping to an uploaded or staged PDF document.
    Executes non-destructive /CropBox modifications locally using PyMuPDF.

    Parameters:
    - file: Uploaded PDF file (optional if session_file_id provided)
    - session_file_id: Session token of previously staged file in RAM
    - left: Left margin trim in points (float >= 0)
    - top: Top margin trim in points (float >= 0)
    - right: Right margin trim in points (float >= 0)
    - bottom: Bottom margin trim in points (float >= 0)
    - apply_to_all: Boolean flag to crop all pages or only target_page
    - target_page: Zero-based page index to crop if apply_to_all is False
    """
    max_bytes = get_max_file_bytes()

    # Create temporary working directory
    temp_dir = Path(tempfile.mkdtemp(prefix="freepdftoolz_crop_"))
    background_tasks.add_task(cleanup_directory, str(temp_dir))

    temp_input_path = temp_dir / "input.pdf"
    filename = "document.pdf"
    file_bytes: Optional[bytes] = None

    if session_file_id:
        staged = FileStagingService.get_staged_file(session_file_id)
        if staged:
            file_bytes, filename = staged
        elif file is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Staged session file expired or not found. Please upload again.",
            )

    if file_bytes is None and file is not None:
        filename = (file.filename or "document.pdf").strip()
        if not filename.lower().endswith(".pdf"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Only PDF files are supported.",
            )
        file_bytes = await file.read()

    if file_bytes is None or len(file_bytes) == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No PDF file or valid session_file_id provided.",
        )

    if len(file_bytes) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File exceeds maximum allowed size of {max_bytes // (1024 * 1024)}MB.",
        )

    temp_output_path = temp_dir / f"{Path(filename).stem}_cropped.pdf"

    try:
        with open(temp_input_path, "wb") as f:
            f.write(file_bytes)

        # Execute PDF cropping
        try:
            crop_pdf(
                input_path=temp_input_path,
                output_path=temp_output_path,
                left=left,
                top=top,
                right=right,
                bottom=bottom,
                apply_to_all=apply_to_all,
                target_page=target_page,
            )
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
                detail="Cropped PDF was not successfully generated.",
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
        logger.exception("Unexpected error cropping PDF: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An error occurred while cropping the PDF: {str(e)}",
        )
