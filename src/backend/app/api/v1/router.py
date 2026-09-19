from fastapi import APIRouter
from app.api.v1.endpoints import (
    ocr,
    jobs,
    config,
    contact,
    tools_info,
    tools_merge,
    tools_split,
    tools_rotate,
    tools_delete_pages,
    tools_extract_pages,
    tools_number_pages,
    tools_compress,
    tools_watermark,
    tools_crop,
    tools_redact,
    tools_sign,
    tools_thumbnails,
)

api_router = APIRouter()
api_router.include_router(ocr.router, prefix="/ocr", tags=["ocr"])
api_router.include_router(jobs.router, prefix="/jobs", tags=["jobs"])
api_router.include_router(config.router, prefix="/config", tags=["config"])
api_router.include_router(contact.router, prefix="/contact", tags=["contact"])
api_router.include_router(tools_info.router, prefix="/tools", tags=["tools"])
api_router.include_router(tools_thumbnails.router, prefix="/tools", tags=["PDF Tools - Thumbnails"])
api_router.include_router(tools_merge.router, prefix="/tools", tags=["PDF Tools - Merge"])
api_router.include_router(tools_split.router, prefix="/tools", tags=["PDF Tools - Split"])
api_router.include_router(tools_rotate.router, prefix="/tools", tags=["PDF Tools - Rotate"])
api_router.include_router(tools_delete_pages.router, prefix="/tools", tags=["PDF Tools - Delete Pages"])
api_router.include_router(tools_extract_pages.router, prefix="/tools", tags=["PDF Tools - Extract Pages"])
api_router.include_router(tools_number_pages.router, prefix="/tools", tags=["PDF Tools - Number Pages"])
api_router.include_router(tools_compress.router, prefix="/tools", tags=["PDF Tools - Compress"])
api_router.include_router(tools_watermark.router, prefix="/tools", tags=["PDF Tools - Watermark"])
api_router.include_router(tools_crop.router, prefix="/tools", tags=["PDF Tools - Crop"])
api_router.include_router(tools_redact.router, prefix="/tools", tags=["PDF Tools - Redact"])
api_router.include_router(tools_sign.router, prefix="/tools", tags=["PDF Tools - Sign"])



