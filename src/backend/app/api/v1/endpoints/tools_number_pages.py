import json
import logging
import os
from pathlib import Path
import shutil
import tempfile
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.services.pdf_number_pages_service import number_pdf_pages
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
            logger.info("Purged temporary number pages directory: %s", path)
    except Exception as e:
        logger.warning("Failed to purge temp directory %s: %s", path, e)


@router.post("/number-pages")
async def number_pages_endpoint(
    background_tasks: BackgroundTasks,
    file: Optional[UploadFile] = File(None),
    session_file_id: Optional[str] = Form(None),
    position: Optional[str] = Form("bottom-center"),
    format: Optional[str] = Form("Page {n} of {total}"),
    skip_cover: bool = Form(False),
    start_page: int = Form(1),
    font_size: float = Form(10.0),
):
    """
    Applies custom page numbers to an uploaded or staged PDF document.
    Enforces canonical size limits and processes locally in ephemeral storage using PyMuPDF.

    Parameters:
    - file: Uploaded PDF file (optional if session_file_id provided)
    - session_file_id: Session token of previously staged file in RAM
    - position: Anchor point (top-left, top-center, top-right, bottom-left, bottom-center, bottom-right)
    - format: Template string with {n} and optional {total}
    - skip_cover: If true, leaves first page untouched
    - start_page: Initial page number value (defaults to 1)
    - font_size: Font size in points (defaults to 10.0)
    """
    max_bytes = get_max_file_bytes()

    # Create temporary working directory
    temp_dir = Path(tempfile.mkdtemp(prefix="freepdftoolz_number_"))
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

        clean_stem = Path(filename).stem
        output_path = temp_dir / f"{clean_stem}_numbered.pdf"

        try:
            result_path = number_pdf_pages(
                input_path=temp_input_path,
                output_path=output_path,
                position=position or "bottom-center",
                format_str=format or "Page {n} of {total}",
                skip_first_page=skip_cover,
                start_number=start_page,
                font_size=font_size,
            )
        except ValueError as val_err:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(val_err),
            )
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Failed to process PDF: {str(exc)}",
            )

        if not result_path.exists():
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Numbered PDF file was not successfully generated.",
            )

        return FileResponse(
            path=str(result_path),
            media_type="application/pdf",
            filename=result_path.name,
            background=background_tasks,
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Unexpected error numbering PDF pages: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An error occurred while numbering PDF pages: {str(e)}",
        )
