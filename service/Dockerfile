# syntax=docker/dockerfile:1

# ---------- Stage 1: build ----------
# Pinned to an exact version, never :latest, so builds are reproducible.
FROM python:3.12.11-slim-bookworm AS builder

# slim-bookworm is a Minimal Debian Bookworm-based image containing the components needed to run Python.

WORKDIR /build

# Dependencies go into a virtualenv so the runtime stage can copy just that
# directory. (Currently empty - the service is stdlib-only.)
RUN python -m venv /opt/venv
#this will create python venv under /opt/venv/
ENV PATH="/opt/venv/bin:$PATH"

#this will add the path /opt/venv/bin to the beginning of existing path, when run: python , it looks under this path for binary file to execute /opt/venv/bin/python 

# Copy requirements first so this layer is cached until dependencies change.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ---------- Stage 2: runtime ----------
FROM python:3.12.11-slim-bookworm

# PYTHONDONTWRITEBYTECODE: don't write .pyc files (works with a read-only
#   root filesystem). PYTHONUNBUFFERED: logs appear immediately in `kubectl logs`.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    PORT=8080

# Non-root user with a fixed numeric UID. Kubernetes' runAsNonRoot check can
# only verify a numeric UID, so the USER line below must be a number.
RUN groupadd --system --gid 10001 app \
 && useradd  --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY --chown=10001:10001 app.py .

USER 10001:10001
EXPOSE 8080

CMD ["python", "app.py"]
