# TASK DISPATCH: Implement UC-030 (Convert PDF to Word .docx via pdf2docx Engine)

> **Ticket:** `UC-030`  
> **Sprint:** `Sprint F3` (FreePDFToolz AI, Conversions & AdSense Launch)  
> **Target File:** [`dispatch-prompts/freepdftoolz/sprint 03/UC-030-dispatch.md`](file:///e:/Non_Office/Dev_Space/vibe_skool/freeOcr/dispatch-prompts/freepdftoolz/sprint%2003/UC-030-dispatch.md)  
> **Governance Target:** [`.agents/AGENTS.md`](file:///e:/Non_Office/Dev_Space/vibe_skool/freeOcr/.agents/AGENTS.md)  

---

## 1. Governance & Rule Preconditions

You are an AI coding assistant working on **FreePDFToolz.me & freeOCR.me**. Before writing ANY code or executing tools:
1. **Read Canonical Governance Rules:** Review [`.agents/AGENTS.md`](file:///e:/Non_Office/Dev_Space/vibe_skool/freeOcr/.agents/AGENTS.md).
2. **Strict Authorization Protocol (Rule 2.1):** You MUST NOT run `git commit` or `git push` without explicit user instruction.
3. **TDD Mandate (Rule 4):** Automated tests in `src/tests/` and `src/frontend/test/` MUST be written and fail BEFORE writing implementation logic.
4. **Branching Protocol:** Work strictly on feature branch `freepdftoolz/UC-030-pdf-to-word` checked out from `dev`. NEVER push directly to `main`.
5. **Local-First & Zero-Cloud (Rule 3):** Local `pdf2docx` Python library execution; zero paid cloud dependencies.

---

## 2. Ticket Specification — UC-030

**Ticket ID:** UC-030  
**Name:** Convert PDF to Word (.docx) via pdf2docx Engine  
**Epic:** Epic 8 (FreePDFToolz AI, Conversions & AdSense Launch)  
**Actor:** Anonymous Web Visitor / FastAPI Engine  
**Trigger:** User navigates to `/pdf-to-word` and uploads a PDF.  

### Preconditions
- [x] Sprint F2 completed and merged into `dev`.
- [ ] Active branch set to `freepdftoolz/UC-030-pdf-to-word` checked out from `dev`:
  ```bash
  git checkout dev
  git checkout -b freepdftoolz/UC-030-pdf-to-word
  ```
- [x] `pdf2docx` package installed in backend environment (`pip install pdf2docx python-docx`).

---

### Main Implementation Steps

#### Step 1: Backend PDF to Word Conversion Service & Endpoint (`src/backend/app/`)
1. Create `src/backend/app/services/pdf_to_docx_service.py`:
   - Function `convert_pdf_to_docx(input_path: Path, output_path: Path, start_page: int = 0, end_page: int | None = None) -> Path`:
     - Instantiates `Converter(str(input_path))`.
     - Converts document using `cv.convert(str(output_path), start=start_page, end=end_page)`.
     - Closes converter with `cv.close()`.
     - Validates generated `.docx` file exists and is a valid ZIP/OpenXML package.
     - Returns `output_path`.
2. Create `src/backend/app/api/v1/endpoints/tools_pdf_to_word.py`:
   - Endpoint `POST /api/v1/tools/pdf-to-word`:
     - Accepts `file: Optional[UploadFile] = File(None)`, `session_file_id: Optional[str] = Form(None)`, optional `start_page: int = Form(1)`, `end_page: int | None = Form(None)`.
     - **Volatile File Session Staging:** If `session_file_id` is passed, loads the PDF file bytes directly from `FileStagingService.get_staged_file(session_file_id)` in RAM, completely eliminating redundant file uploads over the network.
     - Validates PDF format and file size limits against `app_limits_config.json`.
     - Returns converted `.docx` stream (`FileResponse` with `application/vnd.openxmlformats-officedocument.wordprocessingml.document`).
     - Cleans up ephemeral working directory in background tasks.
3. Register router in `src/backend/app/api/v1/router.py`.

#### Step 2: Frontend PDF to Word Conversion Workspace (`src/frontend/`)
1. **Landing Page (`/pdf-to-word` in `src/frontend/lib/pages/pdf_to_word_page.dart`):**
   - Header, subtitle: "Convert PDF to Word (.docx) with editable formatting and table preservation."
   - Ad #1 (`AdSenseBanner()`), dropzone, dynamic limits badge, FAQ accordion.
   - Action-driven navigation: routes immediately to `/pdf-to-word/process`.
2. **Workspace Page (`/pdf-to-word/process` in `src/frontend/lib/pages/pdf_to_word_progress_page.dart`):**
   - Telemetry: `TelemetryService.trackPageView('/pdf-to-word/process')`.
   - Ad #2 (`AdSenseBanner()`) with GAM 60s auto-refresh.
   - **Ultra-Fast Thumbnails & Session Staging Integration:**
     - Uses `PdfThumbnailService.fetchThumbnails(file)` which automatically leverages 200px max bounding box, WebP compression (quality 65 with JPEG fallback), and 16-page initial viewport batching to display the document cover preview.
     - Captures and stores `res.sessionFileId` in state.
   - Document overview card (filename, page count, file size, cover preview thumbnail).
   - Conversion Scope Selector: "All Pages" vs "Custom Page Range".
   - **Primary Action (Zero Double Upload):**
     - "Convert to Word (.docx)" button sends `fields: {'session_file_id': sessionFileId, 'start_page': ..., 'end_page': ...}` with `files: []` via `ApiService.uploadToolFiles()`, executing conversion with 0 upload file bytes.
   - Result card with direct `.docx` download button and Ad #3.
3. Register routes in `src/frontend/lib/main.dart`.

---

## 3. TDD Test Plan (Write First!)

### Backend Tests (`src/tests/test_tools_pdf_to_word.py`):
1. `test_convert_pdf_to_docx_success()`: Converts sample PDF to `.docx` and verifies valid DOCX OpenXML structure (`[Content_Types].xml` in zip).
2. `test_convert_pdf_to_docx_page_subset()`: Converts specific page range and verifies output validity.
3. `test_pdf_to_word_endpoint_success()`: Asserts `POST /api/v1/tools/pdf-to-word` returns HTTP 200 and DOCX content-type.
4. `test_pdf_to_word_endpoint_with_session_file_id()`: Asserts DOCX conversion succeeds using staged `session_file_id` without uploading raw bytes.
5. `test_pdf_to_word_endpoint_non_pdf_returns_400()`: Non-PDF rejected with HTTP 400.

### Frontend Tests (`src/frontend/test/pages/pdf_to_word_page_test.dart`):
1. `test_pdf_to_word_page_renders_dropzone_and_ad()`: Verifies landing page renders dropzone and Ad #1.
2. `test_pdf_to_word_progress_page_renders_overview_and_convert_btn()`: Verifies document overview and action button.
3. `test_scope_selector_switches_between_all_and_custom()`: Verifies toggling page scope controls.

---

## 4. Verification Commands
```powershell
# 1. Run Backend Pytest Suite
$env:PYTHONPATH="src/backend;."
C:\python31315\python.exe -m pytest src/tests/test_tools_pdf_to_word.py -v

# 2. Run Frontend Flutter Test Suite
cd src/frontend
flutter test test/pages/pdf_to_word_page_test.dart
```
