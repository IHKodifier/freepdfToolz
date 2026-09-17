# FreePDFToolz: Deployment & Cloud Infrastructure Guide

> **Canonical Guide:** `DEPLOYMENT.md`  
> **Production URL:** `https://freepdftoolz.me`  
> **Staging URL:** `https://freepdftoolz.web.app`

---

## 1. Overview & Architecture

FreePDFToolz operates on a modern, serverless, zero-maintenance architecture:
- **Frontend:** Flutter Web client served via **Firebase Hosting** with pre-rendered static SEO/AdSense HTML shells.
- **Backend:** FastAPI Python service on **Google Cloud Run** (`freepdftoolz-api`) scaling to zero instances when idle.
- **API Routing:** Firebase Hosting rewrites `/api/**` traffic seamlessly to Cloud Run, eliminating CORS issues.

---

## 2. Google Cloud Platform (GCP) Configuration

| Resource | Staging Environment | Production Environment |
|:---|:---|:---|
| **GCP Project ID** | `freeocr-staging-app` | `freepdftoolz-prod` (or custom GCP project) |
| **GCP Region** | `us-central1` | `us-central1` |
| **Cloud Run Service** | `freepdftoolz-api` | `freepdftoolz-api` |
| **Container Image** | `gcr.io/freeocr-staging-app/freepdftoolz-backend:latest` | `gcr.io/freepdftoolz-prod/freepdftoolz-backend:latest` |
| **Min Instances** | `0` (Scale to Zero) | `0` (Scale to Zero) |
| **Max Instances** | `5` | `10` |
| **Memory / CPU** | 2 GiB / 2 vCPU | 2 GiB / 2 vCPU |
| **Environment Vars** | `ENVIRONMENT=staging`, `API_BASE_URL=https://freepdftoolz.web.app` | `ENVIRONMENT=production`, `API_BASE_URL=https://freepdftoolz.me` |

---

## 3. Firebase Hosting Configuration

In `firebase.json`:
- **Site ID:** `freepdftoolz`
- **Public Directory:** `src/frontend/build/web`
- **Clean URLs:** `true`
- **Trailing Slash:** `false`
- **Rewrites:**
  - `/api/**` -> Cloud Run `serviceId: "freepdftoolz-api"` in `us-central1`
  - `**` -> `/index.html` (Flutter SPA client)

### Custom Domain DNS Records:
- **Type A:** `@` points to Firebase Hosting IPs:
  - `199.36.158.100`
- **Type CNAME:** `www` points to:
  - `freepdftoolz.web.app`

---

## 4. GitHub Actions CI/CD Pipeline

The workflow is defined in [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml).

### Triggers:
- **Push to `dev`:** Runs tests and deploys to **Staging** (`freeocr-staging-app` / `freepdftoolz.web.app`).
- **Push to `main`:** Runs tests and deploys to **Production** (`freepdftoolz-prod` / `https://freepdftoolz.me`).
- **`[skip deploy]` Tag:** Include `[skip deploy]` in your commit message to run automated test suites without triggering cloud deployment.

### Required GitHub Secrets:
Add the following secret under `https://github.com/IHKodifier/freepdfToolz/settings/secrets/actions`:
- `GCP_SA_KEY` (or `GCP_SA_KEY_PDFTOOLZ`): Google Cloud Service Account JSON Key with the following IAM roles:
  - **Cloud Run Admin** (`roles/run.admin`)
  - **Cloud Build Service Account** (`roles/cloudbuild.builds.editor`)
  - **Storage Admin** (`roles/storage.admin`)
  - **Firebase Admin** (`roles/firebase.admin`)
  - **Service Account User** (`roles/iam.serviceAccountUser`)

### Optional GitHub Repository Variables:
Under `Settings -> Secrets and variables -> Actions -> Variables`:
- `FREEPDFTOOLZ_PROD_PROJECT`: Set to your dedicated production GCP project (defaults to `freepdftoolz-prod`).
- `FREEPDFTOOLZ_STAGING_PROJECT`: Set to your staging GCP project (defaults to `freeocr-staging-app`).

---

## 5. Manual CLI Deployment (Alternative)

If deploying manually from your terminal:

```powershell
# 1. Build Frontend
cd src/frontend
flutter pub get
flutter build web --release --no-wasm-dry-run
cd ../..

# 2. Build & Deploy Backend Container
gcloud builds submit src/backend --tag gcr.io/freeocr-staging-app/freepdftoolz-backend:latest --project freeocr-staging-app
gcloud run deploy freepdftoolz-api --image gcr.io/freeocr-staging-app/freepdftoolz-backend:latest --region us-central1 --platform managed --min-instances 0 --max-instances 5 --memory 2Gi --cpu 2 --allow-unauthenticated --project freeocr-staging-app

# 3. Deploy Frontend to Firebase Hosting
firebase deploy --only hosting:freepdftoolz --project freeocr-staging-app
```