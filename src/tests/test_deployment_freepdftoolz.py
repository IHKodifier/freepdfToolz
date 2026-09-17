import json
import re
import sys
from pathlib import Path
import pytest
from fastapi.testclient import TestClient

backend_path = Path(__file__).resolve().parent.parent / "backend"
if str(backend_path) not in sys.path:
    sys.path.insert(0, str(backend_path))

from app.main import app

client = TestClient(app)
ROOT_DIR = Path(__file__).resolve().parent.parent.parent


def test_cloud_run_configuration_scale_to_zero():
    """Validates CI/CD deploy workflow explicitly enforces scale-to-zero Cloud Run flags for FreePDFToolz."""
    workflow_path = ROOT_DIR / ".github" / "workflows" / "deploy.yml"
    assert workflow_path.exists(), "deploy.yml workflow file must exist"

    content = workflow_path.read_text(encoding="utf-8")
    
    # Assert deploy-freepdftoolz job exists
    assert "deploy-freepdftoolz:" in content

    # Assert scale-to-zero flags are enforced
    assert "--min-instances 0" in content, "Cloud Run deploy must enforce --min-instances 0 for zero idle costs"
    assert "--max-instances 5" in content, "Cloud Run deploy must enforce --max-instances 5 to prevent bill spikes"


def test_firebase_hosting_rewrites_config():
    """Validates firebase.json properly defines rewrites and dedicated public directory for freepdftoolz."""
    firebase_json_path = ROOT_DIR / "firebase.json"
    assert firebase_json_path.exists(), "firebase.json must exist"

    with open(firebase_json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    hosting_configs = data.get("hosting")
    assert isinstance(hosting_configs, (list, dict)), "firebase.json hosting must be a configuration dict or multi-site list"

    freepdftoolz_config = None
    if isinstance(hosting_configs, list):
        for item in hosting_configs:
            if item.get("site") == "freepdftoolz" or item.get("target") == "freepdftoolz":
                freepdftoolz_config = item
                break
    elif isinstance(hosting_configs, dict):
        if hosting_configs.get("site") == "freepdftoolz" or hosting_configs.get("target") == "freepdftoolz" or not hosting_configs.get("site"):
            freepdftoolz_config = hosting_configs

    assert freepdftoolz_config is not None, "Hosting configuration for site 'freepdftoolz' must be present"
    assert freepdftoolz_config.get("public") in ("src/frontend/build/web", "src/frontend/build/freepdftoolz_web"), (
        "Site 'freepdftoolz' must point to dedicated build folder"
    )

    rewrites = freepdftoolz_config.get("rewrites", [])
    api_rewrite = next((r for r in rewrites if r.get("source") == "/api/**"), None)
    assert api_rewrite is not None, "API rewrite for /api/** must exist"
    assert api_rewrite.get("run", {}).get("serviceId") == "freepdftoolz-api", "API rewrite must route to freepdftoolz-api Cloud Run service"

    spa_rewrite = next((r for r in rewrites if r.get("source") == "**"), None)
    assert spa_rewrite is not None, "SPA rewrite for ** must exist"
    assert spa_rewrite.get("destination") == "/index.html", "SPA rewrite must point to /index.html"


def test_freepdftoolz_pages_generated_and_ad_compliant():
    """Validates dedicated FreePDFToolz pages and legal compliance links exist."""
    source_dir = ROOT_DIR / "src" / "frontend" / "web"
    if not (source_dir / "index.html").exists():
        source_dir = ROOT_DIR / "src" / "frontend" / "web_pdftoolz"
    assert source_dir.exists(), "web or web_pdftoolz directory must exist"

    required_files = [
        "index.html",
        "about/index.html",
        "contact/index.html",
        "privacy/index.html",
        "terms/index.html",
        "hub/index.html",
        "sitemap.xml",
        "robots.txt",
    ]
    for rel_path in required_files:
        p = source_dir / rel_path
        assert p.exists(), f"Required file {rel_path} must exist in web directory"
        content = p.read_text(encoding="utf-8")
        if rel_path == "robots.txt":
            assert len(content) > 20, f"File {rel_path} must not be empty"
        else:
            assert len(content) > 500, f"File {rel_path} must have substantial content"

    # Verify AdSense cookie policy requirements in privacy policy
    privacy_html = (source_dir / "privacy" / "index.html").read_text(encoding="utf-8")
    assert "aboutads.info" in privacy_html, "Privacy policy must link to aboutads.info"
    assert "google.com/settings/ads" in privacy_html, "Privacy policy must link to Google ad settings"
    assert "Google AdSense" in privacy_html or "DoubleClick" in privacy_html, "Privacy policy must mention Google/AdSense cookies"

    # Verify homepage has editorial content and does not hide it
    index_html = (source_dir / "index.html").read_text(encoding="utf-8")
    assert 'id="editorial-content"' in index_html, "Homepage must include permanent editorial content"
    assert "FreePDFToolz" in index_html, "Homepage must reference FreePDFToolz"


def test_freepdftoolz_build_pipeline_in_deploy_workflow():
    """Validates deploy.yml compiles flutter web release or invokes build script for freepdftoolz."""
    workflow_path = ROOT_DIR / ".github" / "workflows" / "deploy.yml"
    content = workflow_path.read_text(encoding="utf-8")
    assert "flutter build web --release" in content or "build_freepdftoolz_site.ps1" in content, (
        "deploy.yml must compile flutter web release bundle or call build_freepdftoolz_site.ps1 in freepdftoolz deploy job"
    )


def test_health_probe_live_endpoint():
    """Smoke tests health endpoint asserting GET /api/v1/health returns HTTP 200 and healthy status."""
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    data = response.json()
    assert data.get("status") in ("ok", "healthy")


def test_cors_headers_match_freepdftoolz_domain():
    """Verifies backend CORS middleware correctly responds to requests from https://freepdftoolz.me."""
    response = client.options(
        "/api/v1/health",
        headers={
            "Origin": "https://freepdftoolz.me",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert response.status_code == 200
    allow_origin = response.headers.get("access-control-allow-origin")
    assert allow_origin in ("*", "https://freepdftoolz.me")

