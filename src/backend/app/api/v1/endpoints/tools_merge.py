import logging
import os
import shutil
import tempfile
from pathlib import Path
from typing import List, Optional
import json

from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.services.pdf_merge_service import merge_pdfs
from app.services.file_staging_service import FileStagingService

router = APIRouter()
logger = logging.getLogger(__name__)

MAX_FILES_LIMIT = 50
FREE_TIER_MAX_BYTES = 100 * 1024 * 1024  # 100MB


def cleanup_directory(path: str) -> None:
    """Removes temporary working directory and all intermediate files."""
    try:
        if os.path.exists(path):
            shutil.rmtree(path, ignore_errors=True)
            logger.info("Purged temporary merge directory: %s", path)
    except Exception as e:
        logger.warning("Failed to purge temp directory %s: %s", path, e)


@router.post("/merge")
async def merge_pdf_files(
    background_tasks: BackgroundTasks,
    files: Optional[List[UploadFile]] = File(None),
    session_file_ids: Optional[str] = Form(None),
):
    """
    Merges 2 to 50 uploaded or staged PDF documents into a single document in sequential order.
    Executes entirely in local ephemeral storage with zero external cloud dependencies.
    """
    staged_ids: List[str] = []
    if session_file_ids:
        try:
            parsed = json.loads(session_file_ids)
            if isinstance(parsed, list):
                staged_ids = [str(x) for x in parsed]
        except Exception:
            pass

    total_inputs = len(staged_ids) + (len(files) if files else 0)
    if total_inputs < 2:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="At least 2 PDF files are required to merge.",
        )

    if total_inputs > MAX_FILES_LIMIT:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Maximum {MAX_FILES_LIMIT} files can be merged in a single request.",
        )

    # Validate uploaded file formats if any
    if files:
        for file in files:
            filename = (file.filename or "").lower()
            if not filename.endswith(".pdf"):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Only PDF files are supported.",
                )

    # Create isolated temporary directory
    temp_dir = tempfile.mkdtemp(prefix="freepdftoolz_merge_")
    background_tasks.add_task(cleanup_directory, temp_dir)

    temp_input_paths: list[Path] = []
    cumulative_size = 0

    try:
        # 1. Process staged files first
        for idx, sid in enumerate(staged_ids):
            staged = FileStagingService.get_staged_file(sid)
            if not staged:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"Staged session file '{sid}' expired or not found. Please upload again.",
                )
            file_bytes, _ = staged
            cumulative_size += len(file_bytes)
            if cumulative_size > FREE_TIER_MAX_BYTES:
                raise HTTPException(
                    status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    detail="Total file size exceeds the 100MB free limit.",
                )
            dest_path = Path(temp_dir) / f"input_staged_{idx:03d}.pdf"
            with open(dest_path, "wb") as f:
                f.write(file_bytes)
            temp_input_paths.append(dest_path)

        # 2. Process directly uploaded files
        if files:
            for idx, file in enumerate(files):
                dest_path = Path(temp_dir) / f"input_upload_{idx:03d}.pdf"
                size = 0
                with open(dest_path, "wb") as f:
                    while chunk := await file.read(1024 * 1024):  # 1MB chunks
                        size += len(chunk)
                        cumulative_size += len(chunk)
                        if cumulative_size > FREE_TIER_MAX_BYTES:
                            raise HTTPException(
                                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                                detail="Total file size exceeds the 100MB free limit.",
                            )
                        f.write(chunk)
                temp_input_paths.append(dest_path)

        # Output target
        output_pdf_path = Path(temp_dir) / "merged_document.pdf"

        # Execute merge via PyMuPDF service
        merge_pdfs(temp_input_paths, output_pdf_path)

        return FileResponse(
            path=str(output_pdf_path),
            media_type="application/pdf",
            filename="merged_document.pdf",
            background=background_tasks,
        )

    except HTTPException:
        # Re-raise HTTP exceptions to preserve status codes
        raise
    except Exception as exc:
        logger.exception("Error merging PDF documents: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to merge PDF documents: {str(exc)}",
        )
