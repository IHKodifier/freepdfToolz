import io
import json
import base64
from pathlib import Path
import fitz  # PyMuPDF
import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def create_mock_pdf_bytes(page_texts: list[str]) -> bytes:
    """Helper to generate a minimal valid in-memory PDF with specified page text."""
    doc = fitz.open()
    for text in page_texts:
        page = doc.new_page(width=595, height=842)  # A4 standard
        page.insert_text((50, 100), text, fontsize=14)
    pdf_bytes = doc.write()
    doc.close()
    return pdf_bytes


# --- Unit & Integration Tests: POST /api/v1/tools/render-thumbnails ---


def test_render_thumbnails_single_page():
    """AC: When submitting a 1-page PDF, returns page count 1 and valid base64 JPEG thumbnail."""
    pdf = create_mock_pdf_bytes(["Test Page 1 Content"])
    files = {"file": ("document.pdf", io.BytesIO(pdf), "application/pdf")}

    response = client.post("/api/v1/tools/render-thumbnails", files=files)
    assert response.status_code == 200
    data = response.json()

    assert data["status"] == "SUCCESS"
    assert data["total_pages"] == 1
    assert data["rendered_pages"] == 1
    assert len(data["pages"]) == 1

    p0 = data["pages"][0]
    assert p0["page_index"] == 0
    assert p0["page_number"] == 1
    assert p0["width"] == 595.0
    assert p0["height"] == 842.0
    assert p0["image"].startswith("data:image/jpeg;base64,")

    # Validate that base64 decoded image is a valid JPEG
    b64_str = p0["image"].split(",", 1)[1]
    raw_img = base64.b64decode(b64_str)
    assert len(raw_img) > 100
    assert raw_img[:2] == b"\xff\xd8"  # JPEG Magic bytes


def test_render_thumbnails_multi_page():
    """AC: When submitting a 3-page PDF, returns 3 thumbnails in correct order."""
    pdf = create_mock_pdf_bytes(["Page 1", "Page 2", "Page 3"])
    files = {"file": ("multipage.pdf", io.BytesIO(pdf), "application/pdf")}

    response = client.post("/api/v1/tools/render-thumbnails", files=files)
    assert response.status_code == 200
    data = response.json()

    assert data["total_pages"] == 3
    assert data["rendered_pages"] == 3
    assert len(data["pages"]) == 3
    for idx, page in enumerate(data["pages"]):
        assert page["page_index"] == idx
        assert page["page_number"] == idx + 1
        assert page["image"].startswith("data:image/jpeg;base64,")


def test_render_thumbnails_max_pages_limit():
    """AC: When max_pages is specified (e.g. 2 of 4), renders only up to max_pages while reporting total_pages."""
    pdf = create_mock_pdf_bytes(["Page 1", "Page 2", "Page 3", "Page 4"])
    files = {"file": ("four_pages.pdf", io.BytesIO(pdf), "application/pdf")}
    form_data = {"max_pages": "2"}

    response = client.post("/api/v1/tools/render-thumbnails", files=files, data=form_data)
    assert response.status_code == 200
    data = response.json()

    assert data["total_pages"] == 4
    assert data["rendered_pages"] == 2
    assert len(data["pages"]) == 2


def test_render_thumbnails_custom_dpi():
    """AC: Supports custom dpi parameter without errors."""
    pdf = create_mock_pdf_bytes(["Page 1"])
    files = {"file": ("dpi_test.pdf", io.BytesIO(pdf), "application/pdf")}
    form_data = {"dpi": "36"}

    response = client.post("/api/v1/tools/render-thumbnails", files=files, data=form_data)
    assert response.status_code == 200
    data = response.json()
    assert len(data["pages"]) == 1


def test_render_thumbnails_rejects_non_pdf():
    """AC: Non-PDF upload returns HTTP 400 Bad Request."""
    files = {"file": ("test.txt", io.BytesIO(b"Hello world"), "text/plain")}

    response = client.post("/api/v1/tools/render-thumbnails", files=files)
    assert response.status_code == 400
    assert "pdf" in response.json().get("detail", "").lower()
