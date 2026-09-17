# FreePDFToolz & freeOCR: Complete Repository & Workspace Separation Plan

> **Canonical Path:** `dispatch-prompts/repo-separation-plan-freepdftoolz.md`  
> **Purpose:** Step-by-step implementation guide to decouple `freepdftoolz.me` from `freeOCR.me` into two completely isolated local workspaces and upstream GitHub repositories.

---

## 1. Overview & Architecture

### Objectives
1. **Zero Domain / Brand Cross-Bleed:** Isolate all build assets, HTML shells, SEO metadata, and sitemaps so neither property can contaminate the other.
2. **Independent Production Deployments:** Eliminate selective commit tags (`[deploy:freeocr]` vs `[deploy:freepdftoolz]`). A push to `main` in the `freepdftoolz` repository deploys exclusively to `https://freepdftoolz.me`.
3. **AdSense Isolation:** Protect `freeocr.me` during active review, and give `freepdftoolz.me` its own standalone engineering governance.
4. **Minimal Human Overhead:** Automate the migration using scripts, requiring only standard repository creation and secret copying.

> [!IMPORTANT]
> **Mandatory Dedicated Branch Execution:**  
> This separation plan MUST be executed and implemented on a **separate dedicated branch** (e.g., `feature/repo-separation` or `chore/freepdftoolz-decoupling`) checked out from `dev`. In strict compliance with repository engineering governance (`AGENTS.md`), NEVER execute these changes directly on `main` or `dev`.


---

## 2. Inventory of Separation

| Component | `freeOcr` (Origin Repo) | `freepdftoolz` (Target Repo) |
|:---|:---|:---|
| **Local Folder** | `e:\Non_Office\Dev_Space\vibe_skool\freeOcr` | `e:\Non_Office\Dev_Space\vibe_skool\freepdftoolz` |
| **GitHub Remote** | `https://github.com/IHKodifier/freeOcr` | `https://github.com/IHKodifier/freepdftoolz` |
| **Primary Domain** | `https://freeocr.me` | `https://freepdftoolz.me` |
| **GCP Cloud Run** | `freeocr-api` (`freeocr-backend:latest`) | `freepdftoolz-api` (`freepdftoolz-backend:latest`) |
| **Firebase Site** | `freeocr-staging-app` | `freepdftoolz` |
| **GA4 Measurement** | `G-E852V95BXB` | `G-W4D8V33FX1` |
| **Root Route (`/`)** | OCR Hero Dropzone (`HomePage`) | 16-Tool Catalog Hub (`PdfToolsHubPage`) |
| **Backend Engine** | Baidu PaddleOCR, OCRmyPDF, Tesseract | PyMuPDF, pdf2docx, qpdf, python-docx |
| **Backlog & Dispatch Prompts** | `dispatch-prompts/sprints/stage-01/` & Stage 01 trackers | `dispatch-prompts/freepdftoolz/sprint 03/` (UC-028..UC-032) & Stage 03 trackers |

---

## 3. Step-by-Step Execution Workflow

### Phase 1: Manual Prerequisites (User Actions — ~2 Minutes)
1. **Create New Remote GitHub Repository:**
   - Go to [github.com/new](https://github.com/new)
   - Visibility: **Public** (Recommended — gives unlimited free GitHub Actions build minutes on GitHub Free tier) or **Private**
   - **Do NOT** initialize with README, `.gitignore`, or license (keep it completely empty).
   - Alternatively, execute via GitHub CLI:
     ```powershell
     gh repo create IHKodifier/freepdftoolz --public
     ```
2. **Copy GitHub Actions Secrets to the New Repo:**
   In `https://github.com/IHKodifier/freepdftoolz/settings/secrets/actions`, add:
   - `GCP_SA_KEY` (The Google Cloud service account JSON key already used for deployments)

---

### Phase 2: Local Workspace Duplication & Remote Re-binding
Run the following automated PowerShell commands from `e:\Non_Office\Dev_Space\vibe_skool\`:

```powershell
# 1. Clone/copy working directory into the new project workspace
Copy-Item -Path "e:\Non_Office\Dev_Space\vibe_skool\freeOcr" -Destination "e:\Non_Office\Dev_Space\vibe_skool\freepdftoolz" -Recurse -Force

# 2. Navigate to the new workspace
Set-Location "e:\Non_Office\Dev_Space\vibe_skool\freepdftoolz"

# 3. Re-point git origin to the new repository
git remote set-url origin https://github.com/IHKodifier/freepdftoolz.git

# 4. Verify remote
git remote -v
```

---

### Phase 3: Pruning & Decoupling `freepdftoolz` Workspace

Inside `e:\Non_Office\Dev_Space\vibe_skool\freepdftoolz`:

1. **Routing & Home Page:**
   - In `src/frontend/lib/main.dart`: Set the default initial route `/` directly to `PdfToolsHubPage()` (or dedicated `PdfToolWorkspacePage`).
   - Remove OCR dropzone as the default landing view.
2. **Firebase Hosting Isolation (`firebase.json`):**
   - Remove the `freeocr-staging-app` site object.
   - Keep only the `freepdftoolz` site configuration, with `"public": "src/frontend/build/web"`.
3. **CI/CD Simplification (`.github/workflows/deploy.yml`):**
   - Remove `deploy-freeocr` job.
   - Rename workflow to `FreePDFToolz CI/CD Deployment`.
   - Standardize triggers: push to `dev` deploys staging; push to `main` deploys production. (No selective tag parsing required).
4. **Static SEO, Legal Pages & Shell Assets (Zero Rerun Required):**
   - The anti-thin-content remediation for FreePDFToolz is already 100% pre-generated and stored in `src/frontend/web_pdftoolz/`.
   - **Do NOT rerun or recreate content.** Simply promote it directly to the native web folder:
     ```powershell
     Copy-Item -Path "src/frontend/web_pdftoolz/*" -Destination "src/frontend/web" -Recurse -Force
     Remove-Item -Recurse -Force "src/frontend/web_pdftoolz"
     ```
   - This instantly equips the standalone `freepdftoolz` repository with all 25,000+ words of editorial copy, the 16-tool catalog (`/hub`), legal pages (`/about`, `/contact`, `/privacy`, `/terms`), 6 technical whitepapers (`/kb/`), and sitemaps/robots.
   - Retain `product-specs/adsense-content-remediation-freepdftoolz.md` as the canonical AdSense compliance documentation for the repository.
5. **Backend Pruning:**
   - Remove heavy OCR weights/dependencies (`paddleocr`, `tesseract`, etc.) from `src/backend/requirements.txt` to keep the Docker image lightweight and fast-building.
   - Keep PDF operations: `pymupdf` (fitz), `pdf2docx`, `pypdf`, `reportlab`.
6. **Dispatch Tickets & Active Backlog Transfer (Sprint 03):**
   - Several FreePDFToolz use cases are pending implementation (e.g. `UC-028: Split by Chapter`, `UC-029: Edit PDF Text`, and `UC-030: PDF to Word DOCX`).
   - Retain and promote the entire `dispatch-prompts/freepdftoolz/` directory, specifically:
     - `dispatch-prompts/freepdftoolz/sprint 03/UC-028-dispatch.md`
     - `dispatch-prompts/freepdftoolz/sprint 03/UC-029-dispatch.md`
     - `dispatch-prompts/freepdftoolz/sprint 03/UC-030-dispatch.md`
     - `dispatch-prompts/freepdftoolz/sprint 03/UC-032-dispatch.md`
   - Retain the FreePDFToolz sprint trackers in `trackers/stage-03/` (`07.03.01`, `07.03.02`, `07.03.03`) and adapt `trackers/master-tracker.md` to track FreePDFToolz use cases exclusively.
   - Remove OCR-specific dispatch prompts (`dispatch-prompts/sprints/stage-01/`) from the `freepdftoolz` repository.

---

### Phase 4: Pruning Origin `freeOcr` Workspace

> [!NOTE]
> Execute all pruning modifications in `freeOcr` on a dedicated branch checked out from `dev`:
> ```powershell
> cd e:\Non_Office\Dev_Space\vibe_skool\freeOcr
> git checkout dev
> git checkout -b chore/freepdftoolz-decoupling
> ```

Inside `e:\Non_Office\Dev_Space\vibe_skool\freeOcr`:

1. **Firebase Hosting (`firebase.json`):**
   - Remove the `freepdftoolz` hosting site block.
2. **CI/CD Workflow (`deploy.yml`):**
   - Remove `deploy-freepdftoolz` job.
   - Simplify detection logic so any push to `main` deploys solely to `freeocr.me`.
3. **Clean Up Brand Switchers:**
   - Remove `freepdftoolz` brand-switching logic from `index.html`.

---

### Phase 5: Verification & Push

1. **Push New Repository:**
   ```powershell
   cd e:\Non_Office\Dev_Space\vibe_skool\freepdftoolz
   git checkout main
   git push -u origin main
   git checkout dev
   git push -u origin dev
   ```
2. **Run Test Suites in Both Workspaces:**
   - FreePDFToolz: `pytest src/tests/ -v` and `flutter test`
   - FreeOCR: `pytest src/tests/ -v` and `flutter test`
3. **Verify Clean URL Independence:**
   - `curl -sI https://freeocr.me` -> Returns FreeOCR.
   - `curl -sI https://freepdftoolz.me` -> Returns FreePDFToolz.
