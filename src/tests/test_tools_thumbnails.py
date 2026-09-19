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


def test_render_thumbnails_session_file_staging_and_pagination():
    """AC: First request stages file and returns session_file_id; subsequent batch retrieves without file upload."""
    pages = [f"Page {i+1}" for i in range(25)]
    pdf = create_mock_pdf_bytes(pages)
    files = {"file": ("large_doc.pdf", io.BytesIO(pdf), "application/pdf")}
    form_data = {"page_offset": "0", "batch_size": "10"}

    # Initial batch upload
    res1 = client.post("/api/v1/tools/render-thumbnails", files=files, data=form_data)
    assert res1.status_code == 200
    data1 = res1.json()

    assert data1["total_pages"] == 25
    assert data1["rendered_pages"] == 10
    assert data1["has_more"] is True
    assert "session_file_id" in data1
    session_id = data1["session_file_id"]
    assert session_id is not None

    # Subsequent batch retrieval using ONLY session_file_id (no file multipart)
    res2 = client.post(
        "/api/v1/tools/render-thumbnails",
        data={"session_file_id": session_id, "page_offset": "10", "batch_size": "10"},
    )
    assert res2.status_code == 200
    data2 = res2.json()
    assert data2["total_pages"] == 25
    assert data2["rendered_pages"] == 10
    assert data2["page_offset"] == 10
    assert data2["has_more"] is True
    assert data2["pages"][0]["page_index"] == 10

    # Final batch retrieval
    res3 = client.post(
        "/api/v1/tools/render-thumbnails",
        data={"session_file_id": session_id, "page_offset": "20", "batch_size": "10"},
    )
    assert res3.status_code == 200
    data3 = res3.json()
    assert data3["total_pages"] == 25
    assert data3["rendered_pages"] == 5
    assert data3["page_offset"] == 20
    assert data3["has_more"] is False

