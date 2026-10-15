FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /workspace

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install
COPY backend/requirements.txt /workspace/backend/requirements.txt
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r /workspace/backend/requirements.txt

# Copy source code folders
COPY ai-services /workspace/ai-services
COPY backend /workspace/backend

# Install ai-services package
RUN pip install --no-cache-dir -e /workspace/ai-services

# Set working directory and PYTHONPATH to /workspace/backend so `from app...` works
WORKDIR /workspace/backend
ENV PYTHONPATH=/workspace/backend

ENV PORT=8080
EXPOSE 8080

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
