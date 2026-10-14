FROM python:3.12-slim

# Prevent Python from writing .pyc files and buffer stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /workspace

# Install system dependencies required for building Python packages if needed
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
COPY backend/requirements.txt /workspace/backend/requirements.txt
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r /workspace/backend/requirements.txt

# Copy both ai-services and backend to preserve folder layout
COPY ai-services /workspace/ai-services
COPY backend /workspace/backend

# Install ai-services in editable/package mode so `import ai_services` works cleanly
RUN pip install --no-cache-dir -e /workspace/ai-services

# Set working directory to backend so `app.main:app` resolves
WORKDIR /workspace/backend

# Default Cloud Run port is 8080
ENV PORT=8080
EXPOSE 8080

# Start Uvicorn bound to 0.0.0.0:$PORT
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
