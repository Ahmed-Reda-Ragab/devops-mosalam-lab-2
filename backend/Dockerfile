# ---------- build stage: install deps into an isolated venv ----------
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# All runtime deps ship manylinux wheels, so no compiler toolchain is needed.
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /app
COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# ---------- runtime stage: slim image, non-root, only the venv + app ----------
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# Create an unprivileged user to run the app. No apt packages are installed:
# the healthcheck uses Python's stdlib (already in the image) instead of curl,
# so there's no Debian package version to pin against a rolling base image.
RUN groupadd --system appuser \
    && useradd --system --gid appuser --home-dir /app --no-create-home appuser

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY ./app ./app

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/health', timeout=3).status == 200 else 1)"]

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
