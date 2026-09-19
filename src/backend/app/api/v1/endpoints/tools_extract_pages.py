import json
import logging
import os
from pathlib import Path
import shutil
import tempfile
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.services.pdf_extract_pages_service import extract_pdf_pages
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
            logger.info("Purged temporary extract directory: %s", path)
    except Exception as e:
        logger.warning("Failed to purge temp directory %s: %s", path, e)


@router.post("/extract-pages")
async def extract_pages_endpoint(
    background_tasks: BackgroundTasks,
    file: Optional[UploadFile] = File(None),
    session_file_id: Optional[str] = Form(None),
    pages: Optional[str] = Form(None),
    output_mode: Optional[str] = Form("merged"),
):
    """
    Extracts specified pages from an uploaded or staged PDF document.
    Outputs either a single merged PDF or separate PDFs packaged in a ZIP archive.
    Enforces canonical size limits and processes locally in ephemeral storage using PyMuPDF.

    Parameters:
    - file: Uploaded PDF file (optional if session_file_id provided)
    - session_file_id: Session token of previously staged file in RAM
    - pages: Comma-separated list (e.g. '1, 3, 5'), ranges ('2-4'), or JSON array ('[1, 3]')
    - output_mode: 'merged' (default) or 'separate'
    """
    if not pages or not pages.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No pages specified for extraction.",
        )

    max_bytes = get_max_file_bytes()

    # Create temporary working directory
    temp_dir = Path(tempfile.mkdtemp(prefix="freepdftoolz_extract_"))
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

        # Execute page extraction
        try:
            result_path = extract_pdf_pages(
                input_path=temp_input_path,
                pages_to_extract=pages,
                mode=output_mode or "merged",
                output_dir=temp_dir,
                base_name=Path(filename).stem,
            )
        except ValueError as val_err:
            msg = str(val_err)
            if "out of bounds" in msg.lower() or "range" in msg.lower():
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=msg,
                )
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=msg,
            )
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Failed to process PDF: {str(exc)}",
            )

        if not result_path.exists():
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Extracted file was not successfully generated.",
            )

        media_type = (
            "application/zip"
            if result_path.suffix.lower() == ".zip"
            else "application/pdf"
        )

        return FileResponse(
            path=str(result_path),
            media_type=media_type,
            filename=result_path.name,
            background=background_tasks,
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Unexpected error extracting pages from PDF: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An error occurred while extracting PDF pages: {str(e)}",
        )
