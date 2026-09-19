import logging
from pathlib import Path
from typing import Any, Optional, Sequence, Union

import fitz  # PyMuPDF

logger = logging.getLogger(__name__)

DEFAULT_COLORS: dict[str, list[float]] = {
    "highlight": [1.0, 0.9, 0.0],
    "underline": [0.0, 0.4, 0.9],
    "strikeout": [0.8, 0.1, 0.1],
    "rect": [0.85, 0.1, 0.1],
    "text": [0.95, 0.6, 0.0],
    "sticky_note": [0.95, 0.6, 0.0],
}


def parse_color(color: Any, default: list[float]) -> list[float]:
    """Parses a color from RGB list, hex string, or returns default."""
    if not color:
        return default
    if isinstance(color, str):
        c_str = color.strip().lstrip("#")
        if len(c_str) == 6:
            try:
                r = int(c_str[0:2], 16) / 255.0
                g = int(c_str[2:4], 16) / 255.0
                b = int(c_str[4:6], 16) / 255.0
                return [r, g, b]
            except ValueError:
                return default
    if isinstance(color, (list, tuple)) and len(color) >= 3:
        try:
            r, g, b = float(color[0]), float(color[1]), float(color[2])
            if any(val > 1.0 for val in (r, g, b)):
                return [r / 255.0, g / 255.0, b / 255.0]
            return [max(0.0, min(1.0, r)), max(0.0, min(1.0, g)), max(0.0, min(1.0, b))]
        except (ValueError, TypeError):
            return default
    return default


def parse_rect(item: dict[str, Any]) -> Optional[fitz.Rect]:
    """Parses bounding rectangle from various possible formats in annotation dict."""
    if "rect" in item:
        r = item["rect"]
        if isinstance(r, (list, tuple)) and len(r) >= 4:
            x0, y0, x1, y1 = float(r[0]), float(r[1]), float(r[2]), float(r[3])
            # If coordinates were provided as [x, y, w, h]
            if "is_xywh" in item and item["is_xywh"]:
                return fitz.Rect(x0, y0, x0 + x1, y0 + y1)
            # Ensure coordinates form valid non-negative rect
            return fitz.Rect(min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1))
        elif isinstance(r, dict):
            return parse_rect(r)

    # Dict with x0, y0, x1, y1
    if all(k in item for k in ("x0", "y0", "x1", "y1")):
        return fitz.Rect(
            float(item["x0"]),
            float(item["y0"]),
            float(item["x1"]),
            float(item["y1"]),
        )

    # Dict with x, y, width/w, height/h
    x = item.get("x")
    y = item.get("y")
    w = item.get("width", item.get("w"))
    h = item.get("height", item.get("h"))
    if x is not None and y is not None and w is not None and h is not None:
        fx, fy, fw, fh = float(x), float(y), float(w), float(h)
        return fitz.Rect(fx, fy, fx + fw, fy + fh)

    return None


def parse_point(item: dict[str, Any], default_rect: Optional[fitz.Rect] = None) -> fitz.Point:
    """Extracts target point for sticky notes or text annotations."""
    if "point" in item and isinstance(item["point"], (list, tuple)) and len(item["point"]) >= 2:
        return fitz.Point(float(item["point"][0]), float(item["point"][1]))
    if "x" in item and "y" in item:
        return fitz.Point(float(item["x"]), float(item["y"]))
    if default_rect is not None:
        return fitz.Point(default_rect.x0, default_rect.y0)
    return fitz.Point(72.0, 72.0)


def annotate_pdf(
    input_path: Path,
    output_path: Path,
    annotations: list[dict[str, Any]],
) -> Path:
    """
    Applies vector shapes, highlight markup, and text/sticky notes directly to PDF pages.

    Args:
        input_path: Source PDF file.
        output_path: Destination annotated PDF file.
        annotations: List of annotation descriptor dictionaries.

    Returns:
        Path to the saved annotated PDF file.

    Raises:
        ValueError: If document cannot be opened, has 0 pages, or page index is out of bounds.
        RuntimeError: If annotation or document save fails.
    """
    try:
        doc = fitz.open(str(input_path))
    except Exception as exc:
        logger.error("Failed to open PDF %s for annotation: %s", input_path, exc)
        raise ValueError(f"Failed to open PDF document: {exc}") from exc

    try:
        total_pages = len(doc)
        if total_pages == 0:
            raise ValueError("PDF document has 0 pages.")

        for idx, item in enumerate(annotations):
            if not isinstance(item, dict):
                continue

            page_num = item.get("page", item.get("page_index", 0))
            if not isinstance(page_num, int):
                try:
                    page_num = int(page_num)
                except (ValueError, TypeError):
                    page_num = 0

            if page_num < 0 or page_num >= total_pages:
                raise ValueError(
                    f"Page index {page_num} is out of bounds for document with {total_pages} pages."
                )

            page = doc[page_num]
            annot_type = str(item.get("type", "highlight")).lower().strip()
            color = parse_color(item.get("color"), DEFAULT_COLORS.get(annot_type, [1.0, 0.9, 0.0]))
            rect = parse_rect(item)
            opacity = item.get("opacity")
            border_width = float(item.get("border_width", 1.5))

            annot = None

            if annot_type == "highlight":
                if rect is None:
                    continue
                annot = page.add_highlight_annot(rect)
                annot.set_colors(stroke=color)

            elif annot_type == "underline":
                if rect is None:
                    continue
                annot = page.add_underline_annot(rect)
                annot.set_colors(stroke=color)

            elif annot_type == "strikeout":
                if rect is None:
                    continue
                annot = page.add_strikeout_annot(rect)
                annot.set_colors(stroke=color)

            elif annot_type in ("rect", "box", "square"):
                if rect is None:
                    continue
                annot = page.add_rect_annot(rect)
                fill_color = None
                if "fill" in item and item["fill"] is not None:
                    fill_color = parse_color(item["fill"], color)
                annot.set_colors(stroke=color, fill=fill_color)
                annot.set_border(width=border_width)

            elif annot_type in ("text", "sticky_note", "note"):
                point = parse_point(item, rect)
                content = str(item.get("content", item.get("text", "")))
                annot = page.add_text_annot(point, content, icon="Note")
                annot.set_colors(stroke=color)

            if annot is not None:
                if opacity is not None:
                    try:
                        annot.set_opacity(float(opacity))
                    except (ValueError, TypeError):
                        pass
                annot.update()

        output_path.parent.mkdir(parents=True, exist_ok=True)
        doc.save(str(output_path), garbage=3, deflate=True)
        return output_path

    except ValueError:
        raise
    except Exception as exc:
        logger.exception("Error annotating PDF document: %s", exc)
        raise RuntimeError(f"Error annotating PDF: {exc}") from exc
    finally:
        doc.close()
