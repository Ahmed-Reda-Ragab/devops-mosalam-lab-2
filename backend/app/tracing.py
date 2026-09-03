"""OpenTelemetry tracing bootstrap.

Spans are exported over OTLP/gRPC to the OpenTelemetry Collector, which
forwards them to Tempo. Grafana then reads them from Tempo.

Everything here is opt-in and fail-open: if OTEL_SDK_DISABLED=true, or the
collector is unreachable, or the optional otel packages are not installed, the
app serves traffic exactly as it did before. Observability must never be the
reason the API goes down.

Instrumented automatically:
  * FastAPI    - one server span per request, with http.route / status_code
  * SQLAlchemy - a child span per SQL statement (so you see DB time inside the
                 request span, which is the whole point of tracing here)
  * pymemcache - a child span per cache GET/SET, which makes cache misses
                 visible as latency instead of guesswork
  * requests   - outbound HTTP calls, with trace context propagated
  * logging    - injects the active trace/span id into every log record
"""

import logging
import os

logger = logging.getLogger(__name__)

# Log format carrying the trace id. Promtail ships this line to Loki, and the
# Loki datasource's derived field turns `trace_id=<hex>` into a link that opens
# the trace in Tempo — that is the logs -> traces jump in Grafana.
LOG_FORMAT = (
    "%(asctime)s - %(levelname)s - %(name)s - "
    "trace_id=%(otelTraceID)s span_id=%(otelSpanID)s - %(message)s"
)


def _ensure_log_record_defaults() -> None:
    """Guarantee otelTraceID/otelSpanID exist on every LogRecord.

    LOG_FORMAT references those two fields, but OTel's LoggingInstrumentor only
    starts populating them once setup_tracing() has run — and never at all when
    tracing is disabled or the packages are missing. Without this shim, every
    log line emitted before (or without) tracing would fail to format and
    logging would print "--- Logging error ---" instead of the message.

    Installed at import time, so it is in place before logging.basicConfig().
    LoggingInstrumentor later wraps this factory and overwrites the "0"
    placeholders with the real ids whenever a span is active.
    """
    old_factory = logging.getLogRecordFactory()
    if getattr(old_factory, "_otel_defaults_installed", False):
        return

    def record_factory(*args, **kwargs):
        record = old_factory(*args, **kwargs)
        if not hasattr(record, "otelTraceID"):
            record.otelTraceID = "0"
        if not hasattr(record, "otelSpanID"):
            record.otelSpanID = "0"
        return record

    record_factory._otel_defaults_installed = True
    logging.setLogRecordFactory(record_factory)


_ensure_log_record_defaults()


def setup_tracing(app, engine=None) -> bool:
    """Wire up the OTel SDK. Returns True when tracing is active.

    `app` is the FastAPI instance, `engine` the SQLAlchemy engine (optional —
    passing it is what produces the per-query child spans).
    """
    if os.getenv("OTEL_SDK_DISABLED", "").lower() == "true":
        logger.info("OpenTelemetry disabled via OTEL_SDK_DISABLED")
        return False

    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    if not endpoint:
        logger.info("OpenTelemetry not configured (no OTEL_EXPORTER_OTLP_ENDPOINT)")
        return False

    try:
        from opentelemetry import trace
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
        from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
        from opentelemetry.instrumentation.logging import LoggingInstrumentor
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        from opentelemetry.sdk.trace.sampling import ParentBased, TraceIdRatioBased
    except ImportError:
        logger.warning("OpenTelemetry packages not installed — tracing disabled")
        return False

    # service.name is the identity of this app everywhere downstream: it is the
    # node label in Grafana's Service Map and the `service` join key for the
    # trace <-> logs links.
    resource = Resource.create(
        {
            "service.name": os.getenv("OTEL_SERVICE_NAME", "backend"),
            "service.version": os.getenv("OTEL_SERVICE_VERSION", "1.0"),
            "deployment.environment": os.getenv("DEPLOY_ENV", "production"),
        }
    )

    # ParentBased keeps a trace whole: if Traefik already sampled the request
    # in, we honour that decision instead of re-rolling the dice and producing
    # half a trace. The ratio only applies to requests that arrive unsampled.
    sample_ratio = float(os.getenv("OTEL_TRACES_SAMPLER_ARG", "1.0"))
    provider = TracerProvider(
        resource=resource,
        sampler=ParentBased(root=TraceIdRatioBased(sample_ratio)),
    )

    # Batch (not Simple) processor: spans are queued and flushed on a background
    # thread, so the exporter never sits in the request path.
    provider.add_span_processor(
        BatchSpanProcessor(
            OTLPSpanExporter(endpoint=endpoint, insecure=True),
            max_queue_size=2048,
            max_export_batch_size=512,
            schedule_delay_millis=5000,
        )
    )
    trace.set_tracer_provider(provider)

    # excluded_urls: /health is hit every 30s by Docker and /metrics every 15s
    # by Prometheus. Tracing them would bury real traffic in noise.
    FastAPIInstrumentor.instrument_app(
        app,
        tracer_provider=provider,
        excluded_urls="health,metrics",
    )

    LoggingInstrumentor().instrument(set_logging_format=False)

    if engine is not None:
        try:
            from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor

            SQLAlchemyInstrumentor().instrument(
                engine=engine,
                tracer_provider=provider,
                enable_commenter=True,  # tags SQL with trace context in comments
            )
        except ImportError:
            logger.warning("SQLAlchemy instrumentation unavailable")

    # Optional instrumentations — each is best-effort so a missing package never
    # breaks startup.
    for module_path, class_name in (
        ("opentelemetry.instrumentation.pymemcache", "PymemcacheInstrumentor"),
        ("opentelemetry.instrumentation.redis", "RedisInstrumentor"),
        ("opentelemetry.instrumentation.requests", "RequestsInstrumentor"),
    ):
        try:
            module = __import__(module_path, fromlist=[class_name])
            getattr(module, class_name)().instrument(tracer_provider=provider)
        except Exception:
            logger.debug("skipping %s", class_name)

    logger.info(
        "✅ OpenTelemetry tracing enabled (endpoint=%s, sample_ratio=%s)",
        endpoint,
        sample_ratio,
    )
    return True
