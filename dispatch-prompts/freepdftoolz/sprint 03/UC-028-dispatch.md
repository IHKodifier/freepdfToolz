# TASK DISPATCH: Implement UC-028 (Annotate PDF Engine & Drawing Toolbar)

> **Ticket:** `UC-028`  
> **Sprint:** `Sprint F3` (FreePDFToolz AI, Conversions & AdSense Launch)  
> **Target File:** [`dispatch-prompts/freepdftoolz/sprint 03/UC-028-dispatch.md`](file:///e:/Non_Office/Dev_Space/vibe_skool/freeOcr/dispatch-prompts/freepdftoolz/sprint%2003/UC-028-dispatch.md)  
> **Governance Target:** [`.agents/AGENTS.md`](file:///e:/Non_Office/Dev_Space/vibe_skool/freeOcr/.agents/AGENTS.md)  

---

## 1. Governance & Rule Preconditions

You are an AI coding assistant working on **FreePDFToolz.me & freeOCR.me**. Before writing ANY code or executing tools:
1. **Read Canonical Governance Rules:** Review [`.agents/AGENTS.md`](file:///e:/Non_Office/Dev_Space/vibe_skool/freeOcr/.agents/AGENTS.md).
2. **Strict Authorization Protocol (Rule 2.1):** You MUST NOT run `git commit` or `git push` without explicit user instruction.
3. **TDD Mandate (Rule 4):** Automated tests in `src/tests/` and `src/frontend/test/` MUST be written and fail BEFORE writing implementation logic.
4. **Branching Protocol:** Work strictly on feature branch `freepdftoolz/UC-028-annotate` checked out from `dev`. NEVER push directly to `main`.
5. **Local-First & Zero-Cloud (Rule 3):** Local PyMuPDF execution; zero paid cloud dependencies.

---

## 2. Ticket Specification — UC-028

**Ticket ID:** UC-028  
**Name:** Annotate PDF Engine & Drawing Toolbar  
**Epic:** Epic 8 (FreePDFToolz AI, Conversions & AdSense Launch)  
**Actor:** Anonymous Web Visitor / FastAPI Engine  
**Trigger:** User navigates to `/annotate` and uploads a PDF.  

### Preconditions
- [x] Sprint F2 (UC-023 through UC-027) completed and merged into `dev`.
- [ ] Active branch set to `freepdftoolz/UC-028-annotate` checked out from `dev`:
  ```bash
  git checkout dev
  git checkout -b freepdftoolz/UC-028-annotate
  ```
- [x] PyMuPDF (`fitz`) available in backend environment.

---

### Main Implementation Steps

#### Step 1: Backend Annotation Service & Endpoint (`src/backend/app/`)
1. Create `src/backend/app/services/pdf_annotate_service.py`:
   - Function `annotate_pdf(input_path: Path, output_path: Path, annotations: list[dict]) -> Path`:
     - Opens input PDF using `fitz.open(str(input_path))`.
     - Supports annotation types:
       - `highlight`: `page.add_highlight_annot(quads_or_rect)`. Configurable color `[r, g, b]`.
       - `underline`: `page.add_underline_annot(quads_or_rect)`.
       - `strikeout`: `page.add_strikeout_annot(quads_or_rect)`.
       - `rect`: `page.add_rect_annot(fitz.Rect(x, y, x + w, y + h))`. Border color and fill color.
       - `text` / `sticky_note`: `page.add_text_annot(fitz.Point(x, y), content)`.
     - Validates page index bounds (`0 <= page < len(doc)`).
     - Saves document with `doc.save(str(output_path), garbage=3, deflate=True)`.
     - Leaves non-annotated pages completely untouched.
2. Create `src/backend/app/api/v1/endpoints/tools_annotate.py`:
   - Endpoint `POST /api/v1/tools/annotate`:
     - Accepts `file: Optional[UploadFile] = File(None)`, `session_file_id: Optional[str] = Form(None)`, `annotations: str = Form(...)` (JSON string array of annotation objects).
     - **Volatile File Session Staging:** If `session_file_id` is provided, loads the PDF file bytes directly from `FileStagingService.get_staged_file(session_file_id)` in memory, eliminating redundant file uploads over the network.
     - Validates PDF format and file size against `app_limits_config.json`.
     - Streams output PDF (`FileResponse`) and registers background cleanup.
3. Register router in `src/backend/app/api/v1/router.py`.

#### Step 2: Frontend Annotation Workspace (`src/frontend/`)
1. **Landing Page (`/annotate` in `src/frontend/lib/pages/pdf_annotate_page.dart`):**
   - Header, subtitle, Ad #1 (`AdSenseBanner()`), dropzone, dynamic limits badge, FAQ accordion.
   - Action-driven navigation: routes immediately to `/annotate/process` upon file drop/selection.
2. **Workspace Page (`/annotate/process` in `src/frontend/lib/pages/pdf_annotate_progress_page.dart`):**
   - Telemetry: `TelemetryService.trackPageView('/annotate/process')`.
   - Ad #2 (`AdSenseBanner()`) with GAM 60s auto-refresh.
   - **Ultra-Fast Thumbnails & Session Staging Integration:**
     - Uses `PdfThumbnailService.fetchThumbnails(file)` which automatically leverages 200px max bounding box, WebP compression (quality 65 with JPEG fallback), and 16-page initial viewport batching.
     - Captures and holds `res.sessionFileId` in state.
   - Annotation Toolbar:
     - Tools: Highlight, Underline, Box (Rectangle), Sticky Note.
     - Color Palette: Yellow, Green, Cyan, Pink, Red.
     - Stroke Width / Opacity selector.
   - Interactive Preview Canvas with page switcher (`Page X of Y`).
   - **Primary Action (Zero Double Upload):**
     - "Save Annotations & Download" button sends `fields: {'session_file_id': sessionFileId, 'annotations': jsonEncode(annotations)}` with `files: []` via `ApiService.uploadToolFiles()`, executing with 0 upload file bytes.
   - Result card with Ad #3.
3. Register routes in `src/frontend/lib/main.dart`.

---

## 3. TDD Test Plan (Write First!)

### Backend Tests (`src/tests/test_tools_annotate.py`):
1. `test_annotate_highlight_text()`: Verifies highlight annotation added to target page.
2. `test_annotate_rect_box()`: Verifies rectangle bounding box stamped with custom color.
3. `test_annotate_sticky_note()`: Verifies sticky note text annotation added with content.
4. `test_annotate_out_of_bounds_page_raises_error()`: Invalid page index raises `ValueError`.
5. `test_annotate_endpoint_success()`: Asserts `POST /api/v1/tools/annotate` returns HTTP 200 with valid PDF.
6. `test_annotate_endpoint_with_session_file_id()`: Asserts annotation succeeds using staged `session_file_id` without uploading raw bytes.
7. `test_annotate_endpoint_invalid_file()`: Non-PDF rejected with HTTP 400.

### Frontend Tests (`src/frontend/test/pages/pdf_annotate_page_test.dart`):
1. `test_annotate_page_renders_dropzone_and_ad()`: Verifies landing page renders dropzone and Ad #1.
2. `test_annotate_progress_page_renders_toolbar_and_canvas()`: Verifies toolbar (Highlight, Box, Note) and canvas render.
3. `test_selecting_annotation_tool_updates_active_state()`: Verifies tapping tool button updates active tool.
4. `test_page_selector_updates_active_page()`: Verifies page navigation.

---

## 4. Verification Commands
```powershell
# 1. Run Backend Pytest Suite
$env:PYTHONPATH="src/backend;."
C:\python31315\python.exe -m pytest src/tests/test_tools_annotate.py -v

# 2. Run Frontend Flutter Test Suite
cd src/frontend
flutter test test/pages/pdf_annotate_page_test.dart
```
