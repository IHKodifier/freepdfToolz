import io
import fitz  # PyMuPDF
import pytest
from fastapi.testclient import TestClient
from app.main import app

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


def test_merge_rejects_single_file_with_400():
    """AC: When uploading fewer than 2 PDF files, system rejects with HTTP 400."""
    pdf1 = create_mock_pdf_bytes(["Document 1 - Page 1"])
    files = [
        ("files", ("doc1.pdf", io.BytesIO(pdf1), "application/pdf")),
    ]
    response = client.post("/api/v1/tools/merge", files=files)
    assert response.status_code == 400
    assert "At least 2 PDF files are required" in response.json()["detail"]


def test_merge_rejects_non_pdf_file_with_400():
    """AC: System rejects non-PDF uploads with HTTP 400."""
    pdf1 = create_mock_pdf_bytes(["Valid PDF"])
    text_file = b"This is not a PDF file."
    files = [
        ("files", ("doc1.pdf", io.BytesIO(pdf1), "application/pdf")),
        ("files", ("doc2.txt", io.BytesIO(text_file), "text/plain")),
    ]
    response = client.post("/api/v1/tools/merge", files=files)
    assert response.status_code == 400
    assert "Only PDF files are supported" in response.json()["detail"]


def test_merge_two_valid_pdfs_combines_pages_correctly():
    """AC: 2 valid PDFs merge into a single PDF with total combined page count."""
    pdf1 = create_mock_pdf_bytes(["Doc 1 - Page 1", "Doc 1 - Page 2"])
    pdf2 = create_mock_pdf_bytes(["Doc 2 - Page 1"])

    files = [
        ("files", ("first.pdf", io.BytesIO(pdf1), "application/pdf")),
        ("files", ("second.pdf", io.BytesIO(pdf2), "application/pdf")),
    ]
    response = client.post("/api/v1/tools/merge", files=files)
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/pdf"
    assert "attachment; filename=" in response.headers.get("content-disposition", "")

    # Parse resulting PDF bytes
    result_doc = fitz.open(stream=response.content, filetype="pdf")
    assert result_doc.page_count == 3
    assert "Doc 1 - Page 1" in result_doc[0].get_text()
    assert "Doc 1 - Page 2" in result_doc[1].get_text()
    assert "Doc 2 - Page 1" in result_doc[2].get_text()
    result_doc.close()


def test_merge_preserves_reorder_sequence():
    """AC: Output PDF preserves the exact sequence of the files submitted."""
    pdf_alpha = create_mock_pdf_bytes(["ALPHA DOC"])
    pdf_beta = create_mock_pdf_bytes(["BETA DOC"])

    # Submit Beta first, Alpha second
    files = [
        ("files", ("beta.pdf", io.BytesIO(pdf_beta), "application/pdf")),
        ("files", ("alpha.pdf", io.BytesIO(pdf_alpha), "application/pdf")),
    ]
    response = client.post("/api/v1/tools/merge", files=files)
    assert response.status_code == 200

    result_doc = fitz.open(stream=response.content, filetype="pdf")
    assert result_doc.page_count == 2
    assert "BETA DOC" in result_doc[0].get_text()
    assert "ALPHA DOC" in result_doc[1].get_text()
    result_doc.close()


def test_merge_enforces_max_files_limit():
    """AC: System rejects more than 50 files with HTTP 400."""
    pdf = create_mock_pdf_bytes(["Page"])
    files = [
        ("files", (f"doc_{i}.pdf", io.BytesIO(pdf), "application/pdf"))
        for i in range(51)
    ]
    response = client.post("/api/v1/tools/merge", files=files)
    assert response.status_code == 400
    assert "Maximum 50 files" in response.json()["detail"]


def test_merge_with_session_file_ids():
    """AC: Merging works seamlessly using volatile session_file_ids without raw file re-upload."""
    import json
    from app.services.file_staging_service import FileStagingService

    pdf1 = create_mock_pdf_bytes(["Staged Document 1"])
    pdf2 = create_mock_pdf_bytes(["Staged Document 2"])

    stage_id_1 = FileStagingService.store_staged_file("staged1.pdf", pdf1)
    stage_id_2 = FileStagingService.store_staged_file("staged2.pdf", pdf2)

    session_payload = json.dumps([stage_id_1, stage_id_2])

    response = client.post(
        "/api/v1/tools/merge",
        data={"session_file_ids": session_payload},
    )
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/pdf"

    result_doc = fitz.open(stream=response.content, filetype="pdf")
    assert result_doc.page_count == 2
    assert "Staged Document 1" in result_doc[0].get_text()
    assert "Staged Document 2" in result_doc[1].get_text()
    result_doc.close()

