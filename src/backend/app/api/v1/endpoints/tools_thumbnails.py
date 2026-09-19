import base64
import json
import logging
from typing import Optional

import fitz  # PyMuPDF
from fastapi import APIRouter, File, Form, HTTPException, UploadFile, status

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post("/render-thumbnails")
async def render_thumbnails_endpoint(
    file: UploadFile = File(...),
    max_pages: Optional[int] = Form(100),
    dpi: Optional[int] = Form(72),
    password: Optional[str] = Form(None),
):
    """
    Renders high-speed, lightweight visual page thumbnails for an uploaded PDF.
    Executes 100% in volatile memory without writing to disk.

    Parameters:
    - file: Uploaded PDF file stream
    - max_pages: Maximum number of pages to render (default: 100)
    - dpi: Resolution for rendered thumbnails (default: 72 DPI)
    - password: Password for encrypted PDFs (optional)
    """
    filename = (file.filename or "document.pdf").strip()
    if not filename.lower().endswith(".pdf"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only PDF files are supported for thumbnail rendering.",
        )

    try:
        contents = await file.read()
    except Exception as e:
        logger.error("Failed to read uploaded file: %s", e)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Could not read uploaded PDF file.",
        )

    if not contents:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Uploaded file is empty.",
        )

    try:
        doc = fitz.open(stream=contents, filetype="pdf")
    except Exception as e:
        logger.error("PyMuPDF failed to parse PDF document: %s", e)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid or corrupted PDF file: {str(e)}",
        )

    try:
        if doc.is_encrypted:
            if password:
                auth_success = doc.authenticate(password)
                if not auth_success:
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="Invalid password provided for encrypted PDF.",
                    )
            else:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Password required to decrypt this PDF.",
                )

        total_pages = doc.page_count
        effective_max = max(1, min(max_pages or 100, total_pages))
        effective_dpi = max(36, min(dpi or 72, 150))

        pages_data = []
        for i in range(effective_max):
            page = doc.load_page(i)
            rect = page.rect
            pix = page.get_pixmap(dpi=effective_dpi)
            jpg_bytes = pix.tobytes("jpeg", jpg_quality=75)
            b64_img = base64.b64encode(jpg_bytes).decode("utf-8")

            pages_data.append({
                "page_index": i,
                "page_number": i + 1,
                "width": round(rect.width, 1),
                "height": round(rect.height, 1),
                "image": f"data:image/jpeg;base64,{b64_img}",
            })

        return {
            "status": "SUCCESS",
            "total_pages": total_pages,
            "rendered_pages": len(pages_data),
            "pages": pages_data,
        }
    finally:
        doc.close()
