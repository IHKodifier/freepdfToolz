import json
import logging
import os
from pathlib import Path
import shutil
import tempfile
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.services.pdf_annotate_service import annotate_pdf
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
    """Removes temporary working directory and intermediate files."""
    try:
        if os.path.exists(path):
            shutil.rmtree(path, ignore_errors=True)
            logger.info("Purged temporary annotate directory: %s", path)
    except Exception as e:
        logger.warning("Failed to purge temp directory %s: %s", path, e)


@router.post("/annotate")
async def annotate_pdf_endpoint(
    background_tasks: BackgroundTasks,
    file: Optional[UploadFile] = File(None),
    session_file_id: Optional[str] = Form(None),
    annotations: str = Form("[]"),
):
    """
    Applies text highlights, underlines, callout bounding boxes, and sticky notes to a PDF.

    Parameters:
    - file: Uploaded PDF file (optional if session_file_id provided)
    - session_file_id: Session token of previously staged file in RAM disk
    - annotations: JSON string array of annotation objects
    """
    try:
        parsed_annotations = json.loads(annotations)
        if not isinstance(parsed_annotations, list):
            raise ValueError("Annotations payload must be a JSON array of annotation objects.")
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid annotations JSON: {exc}",
        )

    max_bytes = get_max_file_bytes()

    temp_dir = Path(tempfile.mkdtemp(prefix="freepdftoolz_annotate_"))
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

    try:
        with open(temp_input_path, "wb") as f:
            f.write(file_bytes)

        temp_output_path = temp_dir / f"annotated_{filename}"

        annotate_pdf(
            input_path=temp_input_path,
            output_path=temp_output_path,
            annotations=parsed_annotations,
        )

        return FileResponse(
            path=str(temp_output_path),
            media_type="application/pdf",
            filename=f"annotated_{filename}",
            headers={
                "Access-Control-Expose-Headers": "Content-Disposition",
            },
        )

    except HTTPException:
        raise
    except ValueError as val_err:
        logger.warning("Validation error in annotate endpoint: %s", val_err)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(val_err),
        )
    except Exception as exc:
        logger.exception("Failed to process PDF annotation: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to annotate PDF: {exc}",
        )
