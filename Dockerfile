FROM python:3.11-slim

# Prevent Python from writing .pyc files and buffer stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=7860 \
    APP_ENV=production \
    MODEL_DEVICE=cpu \
    PYTHONPATH=/app

WORKDIR /app

# Install minimal OS dependencies for PIL / OpenCV / health probes
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    libglib2.0-0 \
    libgl1 \
    && rm -rf /var/lib/apt/lists/*

# Install PyTorch CPU wheels first (slashes image size and accelerates builds)
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu

# Install backend dependencies
COPY backend/requirements.txt /app/backend/requirements.txt
RUN pip install --no-cache-dir -r /app/backend/requirements.txt

# Copy ML checkpoints and configuration
COPY ml/checkpoints /app/ml/checkpoints
COPY ml/configs /app/ml/configs

# Copy backend application code
COPY backend /app/backend

# Create non-root user (Hugging Face requirement: user 1000 with home /app)
RUN useradd -m -u 1000 appuser && \
    mkdir -p /app/backend/storage && \
    chown -R appuser:appuser /app

USER appuser

# Hugging Face Spaces exposes port 7860 by default
EXPOSE 7860

# Healthcheck probe
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:7860/health || exit 1

# Start Uvicorn adapting to environment PORT or default 8000
CMD ["sh", "-c", "uvicorn backend.app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
