# TASK DISPATCH: Implement UC-029 (Edit Text in PDF Engine & Inline Text Overlays)

> **Ticket:** `UC-029`  
> **Sprint:** `Sprint F3` (FreePDFToolz AI, Conversions & AdSense Launch)  
> **Target File:** [`dispatch-prompts/freepdftoolz/sprint 03/UC-029-dispatch.md`](file:///e:/Non_Office/Dev_Space/vibe_skool/freeOcr/dispatch-prompts/freepdftoolz/sprint%2003/UC-029-dispatch.md)  
> **Governance Target:** [`.agents/AGENTS.md`](file:///e:/Non_Office/Dev_Space/vibe_skool/freeOcr/.agents/AGENTS.md)  

---

## 1. Governance & Rule Preconditions

You are an AI coding assistant working on **FreePDFToolz.me & freeOCR.me**. Before writing ANY code or executing tools:
1. **Read Canonical Governance Rules:** Review [`.agents/AGENTS.md`](file:///e:/Non_Office/Dev_Space/vibe_skool/freeOcr/.agents/AGENTS.md).
2. **Strict Authorization Protocol (Rule 2.1):** You MUST NOT run `git commit` or `git push` without explicit user instruction.
3. **TDD Mandate (Rule 4):** Automated tests in `src/tests/` and `src/frontend/test/` MUST be written and fail BEFORE writing implementation logic.
4. **Branching Protocol:** Work strictly on feature branch `freepdftoolz/UC-029-edit-text` checked out from `dev`. NEVER push directly to `main`.
5. **Local-First & Zero-Cloud (Rule 3):** Local PyMuPDF execution; zero paid cloud dependencies.

---

## 2. Ticket Specification — UC-029

**Ticket ID:** UC-029  
**Name:** Edit Text in PDF Engine & Inline Text Overlays  
**Epic:** Epic 8 (FreePDFToolz AI, Conversions & AdSense Launch)  
**Actor:** Anonymous Web Visitor / FastAPI Engine  
**Trigger:** User navigates to `/edit-text` and uploads a PDF.  

### Preconditions
- [x] Sprint F2 (UC-023 through UC-027) completed and merged into `dev`.
- [ ] Active branch set to `freepdftoolz/UC-029-edit-text` checked out from `dev`:
  ```bash
  git checkout dev
  git checkout -b freepdftoolz/UC-029-edit-text
  ```
- [x] PyMuPDF (`fitz`) installed in backend environment.

---

### Main Implementation Steps

#### Step 1: Backend Text Editing Service & Endpoint (`src/backend/app/`)
1. Create `src/backend/app/services/pdf_edit_text_service.py`:
   - Function `edit_pdf_text(input_path: Path, output_path: Path, replacements: list[dict], new_text_blocks: list[dict]) -> Path`:
     - **Find and Replace Mode**:
       - Searches target page for exact text strings with `page.search_for(find_text)`.
       - Applies redacting blank fill matching background color over old text via `page.add_redact_annot(rect, fill=(1,1,1))` and `page.apply_redactions()`.
       - Inserts replacement text using `page.insert_textbox(rect, replace_text, fontsize=..., fontname="helv", color=...)`.
     - **Free Text Block Insertion Mode**:
       - Adds new custom text boxes anywhere on specified page: `page.insert_text(point, text, fontsize=..., color=...)`.
     - Preserves all unmodified pages and streams.
     - Saves document with `doc.save(str(output_path), garbage=3, deflate=True)`.
2. Create `src/backend/app/api/v1/endpoints/tools_edit_text.py`:
   - Endpoint `POST /api/v1/tools/edit-text`:
     - Accepts `file: Optional[UploadFile] = File(None)`, `session_file_id: Optional[str] = Form(None)`, `replacements: str = Form("[]")`, `text_blocks: str = Form("[]")`.
     - **Volatile File Session Staging:** If `session_file_id` is passed, loads the PDF file bytes directly from `FileStagingService.get_staged_file(session_file_id)` in memory, completely eliminating redundant file uploads over the network.
     - Validates PDF format, JSON payload syntax, and canonical size limits.
     - Returns modified PDF stream (`FileResponse`).
     - Cleans up ephemeral working directory in background tasks.
3. Register router in `src/backend/app/api/v1/router.py`.

#### Step 2: Frontend Text Editing Workspace (`src/frontend/`)
1. **Landing Page (`/edit-text` in `src/frontend/lib/pages/pdf_edit_text_page.dart`):**
   - Displays header, subtitle, Ad #1 (`AdSenseBanner()`), dropzone, dynamic limits badge, FAQ accordion.
   - Action-driven navigation: routes immediately to `/edit-text/process`.
2. **Workspace Page (`/edit-text/process` in `src/frontend/lib/pages/pdf_edit_text_progress_page.dart`):**
   - Telemetry: `TelemetryService.trackPageView('/edit-text/process')`.
   - Ad #2 (`AdSenseBanner()`) with GAM 60s auto-refresh.
   - **Ultra-Fast Thumbnails & Session Staging Integration:**
     - Uses `PdfThumbnailService.fetchThumbnails(file)` which automatically leverages 200px max bounding box, WebP compression (quality 65 with JPEG fallback), and 16-page initial viewport batching.
     - Captures and stores `res.sessionFileId` in state.
   - Dual-Mode Editing Panel:
     - **Find & Replace Tab**: Search phrase input, replacement text input, match count preview, case sensitivity switch.
     - **Add Text Box Tab**: Custom text field, font size slider (10pt - 48pt), text color picker, draggable placement box on page preview.
   - Page Selector (Page X of Y).
   - **Primary Action (Zero Double Upload):**
     - "Apply Text Edits" button sends `fields: {'session_file_id': sessionFileId, 'replacements': ..., 'text_blocks': ...}` with `files: []` via `ApiService.uploadToolFiles()`, executing with 0 upload file bytes.
   - Result card with Ad #3.
3. Register routes in `src/frontend/lib/main.dart`.

---

## 3. TDD Test Plan (Write First!)

### Backend Tests (`src/tests/test_tools_edit_text.py`):
1. `test_edit_pdf_text_replaces_target_phrase()`: Asserts old phrase replaced by new text in `page.get_text()`.
2. `test_edit_pdf_text_inserts_new_text_box()`: Asserts new custom text box inserted at specified coordinates.
3. `test_edit_pdf_text_case_sensitive()`: Verifies case sensitivity toggle honored during search and replace.
4. `test_edit_pdf_endpoint_success()`: Asserts `POST /api/v1/tools/edit-text` returns HTTP 200 with valid PDF.
5. `test_edit_pdf_endpoint_with_session_file_id()`: Asserts text edits succeed using staged `session_file_id` without uploading raw bytes.
6. `test_edit_pdf_endpoint_invalid_file()`: Non-PDF rejected with HTTP 400.

### Frontend Tests (`src/frontend/test/pages/pdf_edit_text_page_test.dart`):
1. `test_edit_text_page_renders_dropzone_and_ad()`: Verifies landing page renders dropzone and Ad #1.
2. `test_edit_text_progress_page_renders_tabs_and_canvas()`: Verifies Find/Replace and Add Text tabs.
3. `test_entering_replacement_text_updates_state()`: Verifies entering replacement text updates controller.
4. `test_page_selector_navigation()`: Verifies switching pages in multi-page document.

---

## 4. Verification Commands
```powershell
# 1. Run Backend Pytest Suite
$env:PYTHONPATH="src/backend;."
C:\python31315\python.exe -m pytest src/tests/test_tools_edit_text.py -v

# 2. Run Frontend Flutter Test Suite
cd src/frontend
flutter test test/pages/pdf_edit_text_page_test.dart
```
