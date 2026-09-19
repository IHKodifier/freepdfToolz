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

from app.services.pdf_split_service import parse_page_ranges, split_pdf
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
    """Removes temporary working directory and intermediate split files."""
    try:
        if os.path.exists(path):
            shutil.rmtree(path, ignore_errors=True)
            logger.info("Purged temporary split directory: %s", path)
    except Exception as e:
        logger.warning("Failed to purge temp directory %s: %s", path, e)


@router.post("/split")
async def split_pdf_endpoint(
    background_tasks: BackgroundTasks,
    file: Optional[UploadFile] = File(None),
    session_file_id: Optional[str] = Form(None),
    mode: str = Form("ranges"),
    ranges: Optional[str] = Form(None),
    split_every: Optional[int] = Form(None),
):
    """
    Splits an uploaded or staged PDF document into multiple documents or extracts page ranges.
    Executes locally in temporary storage with PyMuPDF.

    Modes:
    - 'ranges': Custom range string (e.g. '1-3, 5, 8-10')
    - 'fixed': Split every N pages (split_every)
    - 'all': Extract every single page as a standalone PDF
    """
    max_bytes = get_max_file_bytes()

    # Create temporary scratch directory
    temp_dir = Path(tempfile.mkdtemp(prefix="freepdftoolz_split_"))
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

        # Inspect PDF
        try:
            doc = fitz.open(str(temp_input_path))
            max_pages = len(doc)
            doc.close()
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Uploaded file is corrupted or not a valid PDF: {str(exc)}",
            )

        if max_pages == 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="PDF document contains no pages.",
            )

        # Determine page ranges based on mode
        mode_normalized = (mode or "ranges").strip().lower()

        if mode_normalized == "ranges":
            if not ranges or not ranges.strip():
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="Page range expression is required for custom ranges mode.",
                )
            try:
                page_ranges = parse_page_ranges(ranges, max_pages)
            except ValueError as val_err:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=str(val_err),
                )

        elif mode_normalized == "fixed":
            if split_every is None or split_every < 1:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="split_every parameter must be at least 1 for fixed interval splitting.",
                )
            page_ranges = [
                list(range(i, min(i + split_every, max_pages)))
                for i in range(0, max_pages, split_every)
            ]

        elif mode_normalized == "all":
            page_ranges = [[i] for i in range(max_pages)]

        else:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Invalid split mode '{mode}'. Supported modes are: 'ranges', 'fixed', 'all'.",
            )

        stem = Path(filename).stem or "Document"
        generated_files = split_pdf(temp_input_path, page_ranges, temp_dir, base_name=stem)

        if not generated_files:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to generate any split files.",
            )

        # If only 1 range produced, return single PDF
        if len(page_ranges) == 1:
            single_pdf = generated_files[0]
            return FileResponse(
                path=str(single_pdf),
                media_type="application/pdf",
                filename=single_pdf.name,
                background=background_tasks,
            )

        # Multiple parts: return the created zip archive (last item in generated_files)
        zip_file = generated_files[-1]
        return FileResponse(
            path=str(zip_file),
            media_type="application/zip",
            filename=zip_file.name,
            background=background_tasks,
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Unexpected error splitting PDF: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An error occurred while splitting the PDF: {str(e)}",
        )
