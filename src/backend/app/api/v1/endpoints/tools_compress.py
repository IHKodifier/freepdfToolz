import json
import logging
import os
import shutil
import tempfile
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.services.pdf_compress_service import compress_pdf, VALID_COMPRESSION_LEVELS
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
    """Removes temporary working directory and intermediate compressed files."""
    try:
        if os.path.exists(path):
            shutil.rmtree(path, ignore_errors=True)
            logger.info("Purged temporary compress directory: %s", path)
    except Exception as e:
        logger.warning("Failed to purge temp directory %s: %s", path, e)


@router.post("/compress")
async def compress_pdf_endpoint(
    background_tasks: BackgroundTasks,
    file: Optional[UploadFile] = File(None),
    session_file_id: Optional[str] = Form(None),
    level: str = Form("recommended"),
):
    """
    Compresses an uploaded or staged PDF file with stream optimization, font/object deduplication,
    and adaptive image downsampling according to the specified level.

    Parameters:
    - file: Uploaded PDF file (optional if session_file_id provided)
    - session_file_id: Session token of previously staged file in RAM
    - level: Compression level preset ('recommended', 'extreme', 'low')
    """
    norm_level = (level or "recommended").strip().lower()
    if norm_level not in VALID_COMPRESSION_LEVELS:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Invalid compression level '{level}'. Must be one of {VALID_COMPRESSION_LEVELS}.",
        )

    max_bytes = get_max_file_bytes()

    # Create temporary working directory
    temp_dir = Path(tempfile.mkdtemp(prefix="freepdftoolz_compress_"))
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

    clean_stem = Path(filename).stem
    temp_output_path = temp_dir / f"{clean_stem}_compressed.pdf"

    try:
        with open(temp_input_path, "wb") as f:
            f.write(file_bytes)

        # Execute compression service
        metrics = compress_pdf(
            input_path=temp_input_path,
            output_path=temp_output_path,
            level=norm_level,
        )

        headers = {
            "Content-Disposition": f'attachment; filename="{clean_stem}_compressed.pdf"',
            "X-Original-Size": str(metrics["original_size"]),
            "X-Compressed-Size": str(metrics["compressed_size"]),
            "X-Percent-Saved": str(metrics["percent_saved"]),
            "Access-Control-Expose-Headers": "Content-Disposition, X-Original-Size, X-Compressed-Size, X-Percent-Saved",
        }

        return FileResponse(
            path=str(temp_output_path),
            media_type="application/pdf",
            headers=headers,
        )
    except HTTPException:
        raise
    except ValueError as ve:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(ve),
        )
    except Exception as exc:
        logger.exception("Error during PDF compression: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"PDF compression failed: {str(exc)}",
        )
