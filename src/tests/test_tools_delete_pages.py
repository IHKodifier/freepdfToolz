import io
import json
from pathlib import Path
import fitz  # PyMuPDF
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services.pdf_delete_pages_service import delete_pdf_pages

client = TestClient(app)


def create_mock_pdf_bytes(page_texts: list[str]) -> bytes:
    """Helper to generate a minimal valid in-memory PDF with specified page text."""
    doc = fitz.open()
    for text in page_texts:
        page = doc.new_page(width=595, height=842)  # A4
        page.insert_text((50, 100), text, fontsize=14)
    pdf_bytes = doc.write()
    doc.close()
    return pdf_bytes


# --- Unit Tests: delete_pdf_pages Service ---


def test_delete_pages_removes_specified_pages_accurately(tmp_path: Path):
    """AC: Creates a 5-page document, deletes pages [1, 3], verifies output has exactly 3 pages."""
    pdf_bytes = create_mock_pdf_bytes(["Page 1", "Page 2", "Page 3", "Page 4", "Page 5"])
    input_path = tmp_path / "input.pdf"
    output_path = tmp_path / "output.pdf"
    input_path.write_bytes(pdf_bytes)

    pages_to_delete = [1, 3]
    summary = delete_pdf_pages(input_path, output_path, pages_to_delete)

    assert summary["deleted_pages_count"] == 2
    assert summary["remaining_pages_count"] == 3
    assert summary["total_original_pages"] == 5
    assert output_path.exists()

    result_doc = fitz.open(str(output_path))
    assert result_doc.page_count == 3
    # Check text of remaining pages: original 0 ("Page 1"), original 2 ("Page 3"), original 4 ("Page 5")
    assert "Page 1" in result_doc[0].get_text()
    assert "Page 3" in result_doc[1].get_text()
    assert "Page 5" in result_doc[2].get_text()
    result_doc.close()


def test_delete_pages_handles_duplicate_indices_gracefully(tmp_path: Path):
    """AC: Passing [1, 1, 2] deduplicates indices and produces clean result."""
    pdf_bytes = create_mock_pdf_bytes(["Page 1", "Page 2", "Page 3", "Page 4"])
    input_path = tmp_path / "input.pdf"
    output_path = tmp_path / "output.pdf"
    input_path.write_bytes(pdf_bytes)

    pages_to_delete = [1, 1, 2]
    summary = delete_pdf_pages(input_path, output_path, pages_to_delete)

    assert summary["deleted_pages_count"] == 2
    assert summary["remaining_pages_count"] == 2
    assert summary["total_original_pages"] == 4

    result_doc = fitz.open(str(output_path))
    assert result_doc.page_count == 2
    assert "Page 1" in result_doc[0].get_text()
    assert "Page 4" in result_doc[1].get_text()
    result_doc.close()


def test_delete_pages_service_rejects_100_percent_deletion(tmp_path: Path):
    """AC: Requesting deletion of all pages raises ValueError."""
    pdf_bytes = create_mock_pdf_bytes(["Page 1", "Page 2"])
    input_path = tmp_path / "input.pdf"
    output_path = tmp_path / "output.pdf"
    input_path.write_bytes(pdf_bytes)

    with pytest.raises(ValueError, match="Cannot delete all pages from a PDF"):
        delete_pdf_pages(input_path, output_path, [0, 1])


def test_delete_pages_service_out_of_bounds_page_raises_value_error(tmp_path: Path):
    """AC: Requesting deletion of page beyond document boundary raises ValueError."""
    pdf_bytes = create_mock_pdf_bytes(["Page 1", "Page 2"])
    input_path = tmp_path / "input.pdf"
    output_path = tmp_path / "output.pdf"
    input_path.write_bytes(pdf_bytes)

    with pytest.raises(ValueError, match="out of bounds"):
        delete_pdf_pages(input_path, output_path, [5])


# --- Integration Tests: POST /api/v1/tools/delete-pages ---


def test_delete_pages_rejects_100_percent_deletion_with_400():
    """AC: Requesting deletion of pages [0, 1] on a 2-page document returns HTTP 400 Bad Request."""
    pdf = create_mock_pdf_bytes(["Page 1", "Page 2"])
    files = {"file": ("test_doc.pdf", io.BytesIO(pdf), "application/pdf")}
    data = {"pages": json.dumps([0, 1])}

    response = client.post("/api/v1/tools/delete-pages", files=files, data=data)
    assert response.status_code == 400
    assert "cannot delete all pages" in response.json().get("detail", "").lower()


def test_delete_pages_endpoint_removes_pages_and_streams_pdf():
    """AC: Successfully deletes pages and returns pruned PDF with attachment header."""
    pdf = create_mock_pdf_bytes(["Page A", "Page B", "Page C", "Page D"])
    files = {"file": ("contract.pdf", io.BytesIO(pdf), "application/pdf")}
    data = {"pages": json.dumps([1, 2])}

    response = client.post("/api/v1/tools/delete-pages", files=files, data=data)
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/pdf"
    assert "contract_pruned.pdf" in response.headers.get("content-disposition", "")

    result_doc = fitz.open(stream=response.content, filetype="pdf")
    assert result_doc.page_count == 2
    assert "Page A" in result_doc[0].get_text()
    assert "Page D" in result_doc[1].get_text()
    result_doc.close()


def test_delete_pages_endpoint_comma_separated_format():
    """AC: Supports comma-separated string for page indices."""
    pdf = create_mock_pdf_bytes(["P1", "P2", "P3"])
    files = {"file": ("invoice.pdf", io.BytesIO(pdf), "application/pdf")}
    data = {"pages": "0,2"}

    response = client.post("/api/v1/tools/delete-pages", files=files, data=data)
    assert response.status_code == 200

    result_doc = fitz.open(stream=response.content, filetype="pdf")
    assert result_doc.page_count == 1
    assert "P2" in result_doc[0].get_text()
    result_doc.close()


def test_delete_pages_endpoint_out_of_bounds_returns_422():
    """AC: Submitting page index outside document range returns HTTP 422."""
    pdf = create_mock_pdf_bytes(["Page 1", "Page 2"])
    files = {"file": ("test.pdf", io.BytesIO(pdf), "application/pdf")}
    data = {"pages": json.dumps([99])}

    response = client.post("/api/v1/tools/delete-pages", files=files, data=data)
    assert response.status_code == 422
    assert "out of bounds" in response.json().get("detail", "").lower()


def test_delete_pages_endpoint_rejects_non_pdf():
    """AC: Non-PDF upload returns HTTP 400 Bad Request."""
    files = {"file": ("notes.txt", io.BytesIO(b"Not a PDF"), "text/plain")}
    data = {"pages": json.dumps([0])}

    response = client.post("/api/v1/tools/delete-pages", files=files, data=data)
    assert response.status_code == 400
    assert "pdf" in response.json().get("detail", "").lower()


def test_delete_pages_endpoint_with_session_file_id():
    """AC: Deletion succeeds using session_file_id without re-uploading file bytes."""
    from app.services.file_staging_service import FileStagingService

    pdf = create_mock_pdf_bytes(["A", "B", "C"])
    session_id = FileStagingService.store_staged_file("sample.pdf", pdf)

    # Post with session_file_id and NO file upload
    response = client.post(
        "/api/v1/tools/delete-pages",
        data={"session_file_id": session_id, "pages": json.dumps([1])},
    )
    assert response.status_code == 200

    result_doc = fitz.open(stream=response.content, filetype="pdf")
    assert result_doc.page_count == 2
    assert "A" in result_doc[0].get_text()
    assert "C" in result_doc[1].get_text()
    result_doc.close()

