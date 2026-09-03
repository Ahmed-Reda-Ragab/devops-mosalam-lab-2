import logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator

from .database import engine
from .health import router as health_router
from .routes import router as tasks_router
from .tracing import LOG_FORMAT, setup_tracing

logging.basicConfig(
    level=logging.INFO,
    # Carries trace_id=/span_id= on every line so Grafana can jump from a log
    # line in Loki straight to the matching trace in Tempo. The placeholders
    # are filled by OTel's LoggingInstrumentor (they render as "0" when no span
    # is active, e.g. during startup).
    format=LOG_FORMAT,
)
logger = logging.getLogger("backend")

app = FastAPI(title="Task Manager API", version="1.0")
app.include_router(tasks_router)
app.include_router(health_router)
Instrumentator().instrument(app).expose(app)   # يضيف /metrics

# Distributed tracing -> OTel Collector -> Tempo -> Grafana. No-ops when
# OTEL_EXPORTER_OTLP_ENDPOINT is unset (local runs, tests, CI).
setup_tracing(app, engine=engine)


@app.middleware("http")
async def log_requests(request: Request, call_next):
    logger.info("request=%s method=%s path=%s", request.client.host if request.client else None, request.method, request.url.path)
    try:
        response = await call_next(request)
    except Exception as e:
        logger.exception("request failed")
        raise
    logger.info("response=%s status_code=%s path=%s", response.status_code, request.method, request.url.path)
    return response
