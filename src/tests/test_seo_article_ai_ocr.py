import os
import xml.etree.ElementTree as ET
import pytest
from scripts.build_seo_pages import markdown_to_simple_html

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

def test_sitemap_contains_ai_ocr_article():
    sitemap_path = os.path.join(REPO_ROOT, "src", "frontend", "web", "sitemap.xml")
    assert os.path.exists(sitemap_path), "sitemap.xml must exist"

    tree = ET.parse(sitemap_path)
    root = tree.getroot()
    namespace = {"ns": "http://www.sitemaps.org/schemas/sitemap/0.9"}

    locs = [elem.text.strip() for elem in root.findall(".//ns:loc", namespace)]
    assert any(loc.endswith("/kb/ai-vs-traditional-ocr") for loc in locs), f"Article /kb/ai-vs-traditional-ocr not found in sitemap.xml: {locs}"

def test_ai_ocr_markdown_article_exists_and_detailed():
    md_path = os.path.join(REPO_ROOT, "docs", "blog", "ai-vs-traditional-ocr.md")
    assert os.path.exists(md_path), f"Markdown article must exist at {md_path}"

    with open(md_path, "r", encoding="utf-8") as f:
        content = f.read()

    word_count = len(content.split())
    assert word_count >= 1500, f"Article word count is {word_count}, expected >= 1500 words for deep AdSense E-E-A-T value"
    assert "Document Layout Analysis" in content
    assert "Reading Order Detection" in content
    assert "Tesseract" in content
    assert "PaddleOCR" in content

def test_markdown_to_html_includes_tech_article_schema():
    sample_md = """# Deep Learning AI OCR
## The Heuristic Geometry Wall
Document Layout Analysis transforms traditional OCR.
"""
    html = markdown_to_simple_html(sample_md, "Deep-Learning AI vs Traditional OCR")
    assert "schema.org" in html
    assert "TechArticle" in html
    assert "freeOCR.me" in html
    assert "<h1>" in html
    assert "<h2>" in html
