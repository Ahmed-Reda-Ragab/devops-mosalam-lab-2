import logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator

from .health import router as health_router
from .routes import router as tasks_router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(name)s - %(message)s",
)
logger = logging.getLogger("backend")

app = FastAPI(title="Task Manager API", version="1.0")
app.include_router(tasks_router)
app.include_router(health_router)
Instrumentator().instrument(app).expose(app)   # يضيف /metrics


@app.middleware("http")
async def log_requests(request: Request, call_next):
    logger.info("request=%s method=%s path=%s", request.client.host if request.client else None, request.method, request.url.path)
    try:
        response = await call_next(request)
    except Exception:
        logger.exception("request failed")
        return JSONResponse(status_code=500, content={"detail": "Internal server error"})
    logger.info("response=%s status_code=%s path=%s", response.status_code, request.method, request.url.path)
    return response
