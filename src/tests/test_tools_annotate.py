import io
import json
from pathlib import Path
import fitz  # PyMuPDF
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services.pdf_annotate_service import annotate_pdf
from app.services.file_staging_service import FileStagingService

client = TestClient(app)


def create_mock_pdf_bytes(page_texts: list[str]) -> bytes:
    """Helper to generate a minimal valid in-memory PDF with specified page texts."""
    doc = fitz.open()
    for text in page_texts:
        page = doc.new_page(width=595, height=842)  # Standard A4
        page.insert_text((50, 100), text, fontsize=14)
    pdf_bytes = doc.write()
    doc.close()
    return pdf_bytes


# --- Unit Tests: PDF Annotate Service ---


def test_annotate_highlight_text(tmp_path: Path):
    """
    Verifies highlight annotation is added to target page with custom color
    and leaves other pages untouched.
    """
    pdf_bytes = create_mock_pdf_bytes(["Page 1 Content", "Page 2 Target", "Page 3 End"])
    input_path = tmp_path / "input.pdf"
    input_path.write_bytes(pdf_bytes)
    output_path = tmp_path / "output_highlight.pdf"

    annotations = [
        {
            "page": 1,
            "type": "highlight",
            "rect": [50, 90, 200, 110],
            "color": [1.0, 0.9, 0.0],  # Yellow
        }
    ]

    result = annotate_pdf(input_path, output_path, annotations)
    assert result.exists()

    doc = fitz.open(str(result))
    assert doc.page_count == 3

    # Page 0 has no annotations
    page0 = doc[0]
    assert list(page0.annots()) == []

    # Page 1 has 1 highlight annotation
    page1 = doc[1]
    page1_annots = list(page1.annots())
    assert len(page1_annots) == 1
    assert page1_annots[0].type[1] == "Highlight"

    # Page 2 has no annotations
    page2 = doc[2]
    assert list(page2.annots()) == []
    doc.close()


def test_annotate_rect_box(tmp_path: Path):
    """
    Verifies rectangle bounding box is stamped on the target page.
    """
    pdf_bytes = create_mock_pdf_bytes(["Page 1 Content"])
    input_path = tmp_path / "input_rect.pdf"
    input_path.write_bytes(pdf_bytes)
    output_path = tmp_path / "output_rect.pdf"

    annotations = [
        {
            "page": 0,
            "type": "rect",
            "rect": [100, 150, 250, 250],
            "color": [0.9, 0.1, 0.1],  # Red border
            "border_width": 2.0,
        }
    ]

    result = annotate_pdf(input_path, output_path, annotations)
    assert result.exists()

    doc = fitz.open(str(result))
    page0 = doc[0]
    annots = list(page0.annots())
    assert len(annots) == 1
    assert annots[0].type[1] == "Square"  # PyMuPDF classifies rect as Square
    doc.close()


def test_annotate_sticky_note(tmp_path: Path):
    """
    Verifies sticky note text annotation is added with specific content.
    """
    pdf_bytes = create_mock_pdf_bytes(["Page 1 Document"])
    input_path = tmp_path / "input_note.pdf"
    input_path.write_bytes(pdf_bytes)
    output_path = tmp_path / "output_note.pdf"

    annotations = [
        {
            "page": 0,
            "type": "text",
            "rect": [72, 72, 92, 92],
            "content": "Please review clause 4b carefully.",
            "color": [0.1, 0.8, 0.3],
        }
    ]

    result = annotate_pdf(input_path, output_path, annotations)
    assert result.exists()

    doc = fitz.open(str(result))
    page0 = doc[0]
    annots = list(page0.annots())
    assert len(annots) == 1
    assert annots[0].type[1] == "Text"
    assert annots[0].info.get("content") == "Please review clause 4b carefully."
    doc.close()


def test_annotate_underline_and_strikeout(tmp_path: Path):
    """
    Verifies underline and strikeout annotations are added.
    """
    pdf_bytes = create_mock_pdf_bytes(["Page 1 Document"])
    input_path = tmp_path / "input_markup.pdf"
    input_path.write_bytes(pdf_bytes)
    output_path = tmp_path / "output_markup.pdf"

    annotations = [
        {
            "page": 0,
            "type": "underline",
            "rect": [50, 95, 180, 105],
            "color": [0.0, 0.4, 0.9],
        },
        {
            "page": 0,
            "type": "strikeout",
            "rect": [200, 95, 300, 105],
            "color": [0.8, 0.1, 0.1],
        },
    ]

    result = annotate_pdf(input_path, output_path, annotations)
    assert result.exists()

    doc = fitz.open(str(result))
    page0 = doc[0]
    annots = list(page0.annots())
    assert len(annots) == 2
    types = [a.type[1] for a in annots]
    assert "Underline" in types
    assert "StrikeOut" in types
    doc.close()


def test_annotate_out_of_bounds_page_raises_error(tmp_path: Path):
    """
    Asserts ValueError is raised if target page index is out of document bounds.
    """
    pdf_bytes = create_mock_pdf_bytes(["Single Page Document"])
    input_path = tmp_path / "input_bounds.pdf"
    input_path.write_bytes(pdf_bytes)
    output_path = tmp_path / "output_bounds.pdf"

    annotations = [
        {
            "page": 5,  # Out of bounds
            "type": "highlight",
            "rect": [50, 50, 100, 100],
        }
    ]

    with pytest.raises(ValueError, match="out of bounds"):
        annotate_pdf(input_path, output_path, annotations)


# --- Integration Tests: API Endpoint ---


def test_annotate_endpoint_success():
    """
    Asserts POST /api/v1/tools/annotate returns HTTP 200 with valid PDF bytes.
    """
    pdf_bytes = create_mock_pdf_bytes(["Invoice #1001", "Terms and Conditions"])
    annotations = [
        {
            "page": 0,
            "type": "highlight",
            "rect": [50, 90, 150, 110],
            "color": [1.0, 1.0, 0.0],
        }
    ]

    response = client.post(
        "/api/v1/tools/annotate",
        files={"file": ("invoice.pdf", pdf_bytes, "application/pdf")},
        data={"annotations": json.dumps(annotations)},
    )

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/pdf"
    assert "annotated_invoice.pdf" in response.headers.get("content-disposition", "")

    doc = fitz.open(stream=response.content, filetype="pdf")
    assert doc.page_count == 2
    page0 = doc[0]
    annots = list(page0.annots())
    assert len(annots) == 1
    doc.close()


def test_annotate_endpoint_with_session_file_id():
    """
    Asserts annotation succeeds using staged session_file_id without uploading raw file bytes.
    """
    pdf_bytes = create_mock_pdf_bytes(["Agreement Contract"])
    session_id = FileStagingService.store_staged_file(filename="contract.pdf", data=pdf_bytes)

    annotations = [
        {
            "page": 0,
            "type": "rect",
            "rect": [60, 80, 200, 180],
            "color": [0.0, 0.5, 1.0],
        }
    ]

    response = client.post(
        "/api/v1/tools/annotate",
        data={
            "session_file_id": session_id,
            "annotations": json.dumps(annotations),
        },
    )

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/pdf"

    doc = fitz.open(stream=response.content, filetype="pdf")
    page0 = doc[0]
    assert len(list(page0.annots())) == 1
    doc.close()


def test_annotate_endpoint_invalid_file():
    """
    Asserts non-PDF files are rejected with HTTP 400.
    """
    response = client.post(
        "/api/v1/tools/annotate",
        files={"file": ("test.txt", b"plain text content", "text/plain")},
        data={"annotations": json.dumps([])},
    )
    assert response.status_code == 400
    assert "PDF" in response.json()["detail"]


def test_annotate_endpoint_invalid_json():
    """
    Asserts malformed annotations JSON string is rejected with HTTP 400.
    """
    pdf_bytes = create_mock_pdf_bytes(["Test Doc"])
    response = client.post(
        "/api/v1/tools/annotate",
        files={"file": ("doc.pdf", pdf_bytes, "application/pdf")},
        data={"annotations": "not-a-valid-json-string"},
    )
    assert response.status_code == 400
    assert "Invalid annotations JSON" in response.json()["detail"]
