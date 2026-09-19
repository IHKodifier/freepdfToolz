import json
import logging
import os
from pathlib import Path
import shutil
import tempfile
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.services.pdf_watermark_service import watermark_pdf
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
            logger.info("Purged temporary watermark directory: %s", path)
    except Exception as e:
        logger.warning("Failed to purge temp directory %s: %s", path, e)


@router.post("/watermark")
async def watermark_pdf_endpoint(
    background_tasks: BackgroundTasks,
    file: Optional[UploadFile] = File(None),
    session_file_id: Optional[str] = Form(None),
    watermark_type: str = Form("text"),
    text: Optional[str] = Form("CONFIDENTIAL"),
    image: Optional[UploadFile] = File(None),
    rotation: float = Form(-45.0),
    opacity: float = Form(0.3),
    font_size: float = Form(48.0),
):
    """
    Applies custom text or transparent image watermark to an uploaded or staged PDF document.
    Enforces canonical size limits and processes locally in ephemeral storage using PyMuPDF.

    Parameters:
    - file: Uploaded PDF file (optional if session_file_id provided)
    - session_file_id: Session token of previously staged file in RAM
    - watermark_type: 'text' or 'image'
    - text: Watermark text string
    - image: Optional logo image file (PNG / JPG)
    - rotation: Rotation angle in degrees (e.g. -45, 0, 45)
    - opacity: Opacity between 0.05 and 1.0 (defaults to 0.3)
    - font_size: Font size in points (defaults to 48.0)
    """
    norm_type = (watermark_type or "text").strip().lower()
    if norm_type not in {"text", "image"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid watermark type: '{watermark_type}'. Supported: 'text', 'image'.",
        )

    max_bytes = get_max_file_bytes()

    # Create temporary working directory
    temp_dir = Path(tempfile.mkdtemp(prefix="freepdftoolz_watermark_"))
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

        image_path: Optional[Path] = None
        if norm_type == "image":
            if image is None:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Logo image is required when watermark_type is 'image'.",
                )
            img_ext = Path(image.filename or "logo.png").suffix or ".png"
            image_path = temp_dir / f"watermark_logo{img_ext}"
            with open(image_path, "wb") as f_img:
                while chunk := await image.read(1024 * 1024):
                    f_img.write(chunk)

        clean_stem = Path(filename).stem
        output_path = temp_dir / f"{clean_stem}_watermarked.pdf"

        try:
            result_path = watermark_pdf(
                input_path=temp_input_path,
                output_path=output_path,
                watermark_type=norm_type,
                text=text or "CONFIDENTIAL",
                image_path=image_path,
                rotation=rotation,
                opacity=opacity,
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
                detail=f"Failed to watermark PDF: {str(exc)}",
            )

        if not result_path.exists():
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Watermarked PDF file was not successfully generated.",
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
        logger.exception("Unexpected error watermarking PDF: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An error occurred while watermarking PDF: {str(e)}",
        )
