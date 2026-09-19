import json
import logging
import os
import shutil
import tempfile
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.services.pdf_redact_service import redact_pdf
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
            logger.info("Purged temporary redact directory: %s", path)
    except Exception as e:
        logger.warning("Failed to purge temp directory %s: %s", path, e)


@router.post("/redact")
async def redact_pdf_endpoint(
    background_tasks: BackgroundTasks,
    file: Optional[UploadFile] = File(None),
    session_file_id: Optional[str] = Form(None),
    search_phrase: Optional[str] = Form(None),
    rects_json: Optional[str] = Form(None),
    case_sensitive: bool = Form(False),
):
    """
    Applies permanent cryptographic redaction to an uploaded or staged PDF document.
    Purges text glyphs and raster pixel streams using PyMuPDF.

    Parameters:
    - file: Uploaded PDF document (optional if session_file_id provided)
    - session_file_id: Session token of previously staged file in RAM
    - search_phrase: Keyword or text phrase to redact across document
    - rects_json: Optional JSON array of redaction rects [{'page_index': 0, 'x0': 0, ...}]
    - case_sensitive: Whether keyword matching is case-sensitive
    """
    clean_phrase = (search_phrase or "").strip()
    parsed_rects = None

    if rects_json and rects_json.strip():
        try:
            parsed = json.loads(rects_json)
            if isinstance(parsed, list):
                parsed_rects = parsed
            else:
                raise ValueError("rects_json must be a JSON array.")
        except Exception as json_err:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid rects_json format: {json_err}",
            )

    if not clean_phrase and not parsed_rects:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="At least one redaction target (search_phrase or rects_json) must be specified.",
        )

    max_bytes = get_max_file_bytes()

    # Create temporary working directory
    temp_dir = Path(tempfile.mkdtemp(prefix="freepdftoolz_redact_"))
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

    raw_stem = Path(filename).stem
    temp_output_path = temp_dir / f"{raw_stem}_redacted.pdf"

    try:
        with open(temp_input_path, "wb") as f:
            f.write(file_bytes)

        # Execute PDF Redaction
        try:
            redact_pdf(
                input_path=temp_input_path,
                output_path=temp_output_path,
                search_phrase=clean_phrase or None,
                rects=parsed_rects,
                case_sensitive=case_sensitive,
            )
        except ValueError as val_err:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=str(val_err),
            )
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Failed to process PDF redaction: {str(exc)}",
            )

        if not temp_output_path.exists():
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Redacted PDF was not successfully generated.",
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
        logger.exception("Unexpected error redacting PDF: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An error occurred while redacting the PDF: {str(e)}",
        )
