# Antigravity Agent Rules — FreePDFToolz Engineering Governance

> Engineering governance for **FreePDFToolz** (100% Free Online PDF Suite & AI Document Intelligence Platform). Read this before any code change.  
> Master Spec: `product-specs/08-master-prd.md` | Backlog: `product-specs/06a-use-case-tickets.md` | Master Tracker: `trackers/master-tracker.md`

---

## 1. Directory Location & Rule Loading
- **Canonical Path:** This file lives at [`.agents/AGENTS.md`](file:///e:/Non_Office/Dev_Space/vibe_skool/freepdftoolz/.agents/AGENTS.md) as the single canonical engineering governance document for this repository.
- **Purpose:** Antigravity and other agentic AI assistants automatically discover and enforce directives from this file across all coding sessions in this workspace.

---

## 2. Git Branch Protection & Workflow
- **`main` / `master` (Production):** NEVER commit or push code directly to `main`. This branch is strictly for production releases merged from `dev`.
- **`dev` (Staging):** Protected staging branch. All feature work must take place on dedicated `sprint/sprint-XX` or `feature/UC-XXX` branches checked out from `dev`.
- **Initial Setup Workflow:**
  1. Commit initial project configuration and specs to `main`.
  2. Checkout staging branch `dev`: `git checkout -b dev`.
  3. Checkout sprint branch `sprint/sprint-01` from `dev`: `git checkout -b sprint/sprint-01`.
- **Merging Protocol:** Only propose or execute a PR/merge from `sprint/sprint-XX` into `dev` when **100% of automated tests pass locally**.
- **Commit Format:** `feat(UC-XXX): brief description` or `fix(UC-XXX): brief description`.

### 2.1 Strict Commit & Push Authorization Protocol
- **NO Unprompted Local Commits:** The agent MUST NEVER run `git commit` locally without explicit user instruction. The user selects which files are committed and instructs when to execute local commits.
- **NO Unprompted Remote Pushes:** The agent MUST NEVER execute `git push` to any remote repository without explicit user instructions to publish code to remote.

### 2.2 FreePDFToolz Deployment Protocol
- **Standalone Continuous Deployment:** Pushing or merging to `dev` automatically deploys to Staging (`freepdftoolz.web.app`), and pushing or merging to `main` automatically deploys to Production (`https://freepdftoolz.me`).
- **Skip Deployment:** Include `[skip deploy]` in the commit message if you only want to execute automated test suites without triggering cloud deployment.
- **No Interactive Target Prompts:** Do NOT prompt the user with domain selection modals (`ask_question`). All pushes in this repository directly target `freepdftoolz`.

---

## 3. Local-First & Zero-Cloud Execution
- **Local Development:** Run backend and OCR services locally (Python 3.13.5 + FastAPI + SQLite `dev.db` + Redis) without mandatory cloud dependencies during feature development.
- **Privacy & File Lifecycle:** Uploaded files must be processed securely in Linux `tmpfs` RAM disk and cleaned up immediately after processing.
- **Cost Protection:** Do NOT spin up external paid cloud OCR APIs or paid cloud infrastructure during routine local feature development. Use local open-source OCR engines (e.g. Baidu's Unlimited OCR AI Model ~6 GB / OCRmyPDF / Tesseract). Both CPU & GPU GCP instances scale to 0 when idle.

---

## 4. TDD & API-First Mandate
- **Test-First Development:** Before writing implementation code or feature logic, create or update automated test files in `./src/tests/unit/` or `./src/tests/integration/`.
- **100% API Decoupling:** The Flutter frontend must NEVER interact directly with underlying database models or raw file parsers. All requests route through FastAPI/REST endpoints governed by schema models.
- **Every Acceptance Criterion:** Every testable acceptance criterion in `06a-use-case-tickets.md` must have a corresponding test assertion.

---

## 5. Automatic Hierarchical Tracker Maintenance
- Whenever a task, feature, or test suite is completed or updated:
  1. Record test names and Pass/Fail results in the active sprint tracker (`trackers/stage-01/sprints/07.01.XX-tracker.md`).
  2. Update the task status in the stage tracker (`trackers/stage-01/07.01-tracker.md`).
  3. Update the overall sprint completion percentage in the master tracker (`trackers/master-tracker.md`).
- **Graphify MCP Knowledge Graph:** Incrementally update the Graphify MCP knowledge graph after completed tickets to lower AI context load and maintain symbol relationships.

---

## 6. Sprint Handoff Prompt Generation
- **End-of-Sprint Protocol:** At the end of every sprint (once 100% of DoD criteria and local tests pass), the agent MUST automatically generate a structured Handoff Prompt file indicating both the completed sprint and the upcoming sprint (e.g. `handoff-sprint-01-to-02.md`) and save it in `handoff-prompts/sprints/stage-01/handoff-sprint-01-to-02.md`.
- **Handoff Content:** Summary of completed user stories/tasks, test results, branch merge status, updated tracker links, and initial prompts/goals for the subsequent sprint.

---

## 7. Execution Commands & Boundary Matrix

### Quick Commands
- Start Backend Local: `.\scripts\start_backend.ps1`
- Run Backend Tests: `pytest src/tests/ -v`
- Start Flutter Web Client: `cd src/frontend; flutter run -d chrome`
- Run Frontend Tests: `cd src/frontend; flutter test`

### Governance Boundaries
| Always | Ask First | Never |
|:---|:---|:---|
| Write failing tests before implementation (TDD) | Spinning up paid cloud APIs/resources | Commit code locally without explicit user instruction |
| Work one ticket (`UC-XXX`) at a time | Adding new core dependencies | Push code to remote without explicit user instruction |
| Purge temp files from RAM disk after conversion | Changing database or API schemas | Commit or push directly to `main` |
| Update Graphify MCP knowledge graph | Adding external cloud integrations | Commit `.env` secrets or credentials |
| | | Delete or weaken failing tests |

---

## 8. Project Structure
```
freeOcr/
├── .agents/                       # Custom agent skills & local rules
│   └── AGENTS.md                  # Engineering governance rules (canonical)
├── .github/                       # GitHub Actions workflows & PR templates
├── dispatch-prompts/              # Saved zero-context ticket dispatch prompts
│   └── sprints/
│       └── stage-01/              # Per-sprint ticket prompts (UC-000a-dispatch.md...)
├── handoff-prompts/               # Stage & Sprint handoff prompts
│   ├── specs-planning/
│   └── sprints/
│       └── stage-01/
├── product-specs/                 # All Product Specifications & Master PRD
├── scripts/                       # Local development & setup scripts
├── trackers/                      # Live hierarchical backlog trackers
│   ├── master-tracker.md          # Rollup Master Tracker
│   └── stage-01/
│       └── sprints/               # Per-sprint trackers (07.01.01-tracker.md...)
└── src/                           # Application source code
    ├── backend/                   # Python 3.13.5 FastAPI OCR Service
    ├── frontend/                  # Flutter Web / Cross-Platform UI Client
    └── tests/                     # Automated Test Suite (Pytest & Flutter Test)
```
