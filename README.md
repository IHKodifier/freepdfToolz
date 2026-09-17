# FreePDFToolz (freepdftoolz.me)

> **Free, Private & Instant Online PDF Tools**  
> 100% In-Memory Processing • Zero File Retention • No Registration Required

[![FreePDFToolz CI/CD Deployment](https://github.com/IHKodifier/freepdfToolz/actions/workflows/deploy.yml/badge.svg)](https://github.com/IHKodifier/freepdfToolz/actions/workflows/deploy.yml)
[![Live Site](https://img.shields.io/badge/Production-freepdftoolz.me-blue)](https://freepdftoolz.me)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 🚀 Overview

FreePDFToolz provides a comprehensive suite of 16 high-performance PDF manipulation utilities built with **Flutter Web** and **FastAPI / PyMuPDF**. All processing runs securely in ephemeral RAM with immediate zero-retention cleanup.

### Included PDF Tools:
1. **Merge PDF:** Combine multiple PDF documents with drag-and-drop page reordering.
2. **Split PDF:** Extract custom page ranges, split by fixed increments, or separate all pages.
3. **Rotate PDF:** Permanent 90°/180°/270° orientation correction with live thumbnails.
4. **Delete Pages:** Visual page selector to remove unwanted pages.
5. **Extract Pages:** Extract individual or ranges of pages into standalone PDFs or ZIP bundles.
6. **Number Pages:** Custom header/footer page numbering with format and margin controls.
7. **Compress PDF:** Multi-tier compression (Extreme, Recommended, Low) to reduce file sizes.
8. **Watermark PDF:** Add text or PNG logo overlays with opacity, angle, and position controls.
9. **Crop PDF:** Visual margin cropping with bounding box presets.
10. **Redact PDF:** True cryptographic redaction (destroys text glyphs and vectors).
11. **Sign PDF:** Draw, type, or upload transparent digital signatures.
12. **OCR PDF:** Searchable PDF extraction powered by high-accuracy neural OCR.
13. **PDF to Word (DOCX):** Editable Microsoft Word document conversion (*Backlog: UC-030*).
14. **PDF to Excel:** Structured spreadsheet extraction.
15. **Protect & Unlock PDF:** AES-256 password encryption and decryption.
16. **Split by Chapter:** Bookmark and outline-based splitting (*Backlog: UC-028*).

---

## 🛠️ Tech Stack

- **Frontend:** Flutter Web (Dart 3.x), Material 3, Responsive Layouts.
- **Backend:** FastAPI (Python 3.13), PyMuPDF (Fitz), pdf2docx, ReportLab.
- **Hosting & Infrastructure:**
  - Frontend: **Firebase Hosting** (`freepdftoolz` site)
  - Backend: **Google Cloud Run** (`freepdftoolz-api` scaling to zero instances when idle)
- **CI/CD:** GitHub Actions with automated unit & widget test gates.

---

## 📦 Local Development

### Prerequisites:
- Flutter SDK (stable channel)
- Python 3.13+
- Git

### Running Frontend:
```powershell
cd src/frontend
flutter pub get
flutter run -d chrome
```

### Running Backend:
```powershell
cd src/backend
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

### Running Tests:
```powershell
# Frontend Widget Tests (120 tests)
cd src/frontend
flutter test

# Backend Tests (103 tests)
pytest src/tests/ -k "test_tools_" -v
```

---

## 🌐 Deployment

See [DEPLOYMENT.md](DEPLOYMENT.md) for full GCP and Firebase deployment instructions.