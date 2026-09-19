import json
import logging
import os
from pathlib import Path
import shutil
import tempfile
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.services.pdf_sign_service import sign_pdf
from app.services.file_staging_service import FileStagingService

router = APIRouter()
logger = logging.getLogger(__name__)

CONFIG_PATH = Path(__file__).parent.parent.parent / "app_limits_config.json"
DEFAULT_MAX_FILE_BYTES = 100 * 1024 * 1024  # 100MB
SUPPORTED_IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp"}


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
            logger.info("Purged temporary sign directory: %s", path)
    except Exception as e:
        logger.warning("Failed to purge temp directory %s: %s", path, e)


@router.post("/sign")
async def sign_pdf_endpoint(
    background_tasks: BackgroundTasks,
    file: Optional[UploadFile] = File(None),
    session_file_id: Optional[str] = Form(None),
    signature: UploadFile = File(...),
    page: int = Form(1),
    x: float = Form(100.0),
    y: float = Form(100.0),
    width: float = Form(150.0),
    height: float = Form(60.0),
):
    """
    Applies an electronic signature stamp image to a specified page and coordinate box of a PDF.

    Parameters:
    - file: Uploaded PDF file (optional if session_file_id provided)
    - session_file_id: Session token of previously staged file in RAM
    - signature: Signature image file (PNG / JPG / WEBP)
    - page: 1-indexed target page number
    - x: Top-left X coordinate in PDF points
    - y: Top-left Y coordinate in PDF points
    - width: Signature width in PDF points
    - height: Signature height in PDF points
    """
    sig_filename = (signature.filename or "signature.png").strip()
    sig_ext = Path(sig_filename).suffix.lower()
    if sig_ext not in SUPPORTED_IMAGE_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only PNG, JPG, or WEBP image signatures are supported.",
        )

    if page < 1:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Target page number must be >= 1. Received: {page}.",
        )

    max_bytes = get_max_file_bytes()

    temp_dir = Path(tempfile.mkdtemp(prefix="freepdftoolz_sign_"))
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

        signature_bytes = await signature.read()
        if not signature_bytes:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Signature file is empty.",
            )

        temp_output_path = temp_dir / f"signed_{filename}"

        # Internal target_page is 0-indexed
        sign_pdf(
            input_path=temp_input_path,
            output_path=temp_output_path,
            signature_bytes=signature_bytes,
            target_page=page - 1,
            x=x,
            y=y,
            width=width,
            height=height,
        )

        return FileResponse(
            path=str(temp_output_path),
            media_type="application/pdf",
            filename=f"signed_{filename}",
            headers={
                "Access-Control-Expose-Headers": "Content-Disposition",
            },
        )

    except HTTPException:
        raise
    except ValueError as val_err:
        logger.warning("Validation error in sign endpoint: %s", val_err)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(val_err),
        )
    except Exception as exc:
        logger.exception("Failed to process signature: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to apply signature to PDF: {exc}",
        )
