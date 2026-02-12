# PSEUDOCODE: Application Image
# 1. Inherit from the Python Middleware
FROM local/python_middleware:latest AS app_final

# 2. Dependency Caching Layer
# Copy only requirements first. Docker caches this layer if the file hasn't changed.
COPY --chown=secureuser:pipeline src/requirements.txt .

# 3. Install Libraries
# Install Flask, Gunicorn, Requests, Firestore (User Mode)
RUN pip install --no-cache-dir -r requirements.txt

# 4. Application Logic
# Copy the actual source code (app.py) and any static files (e.g., public/) into the image
COPY --chown=secureuser:pipeline public/ public/
COPY --chown=secureuser:pipeline src/ .

# 5. Runtime Configuration
# Cloud Run injects the PORT env var (defaults to 8080)
ENV PORT=8080
EXPOSE 8080

# 6. Entrypoint
# Start the Gunicorn server binding to the correct port
CMD ["gunicorn", "--bind", ":8080", "--workers", "1", "--threads", "8", "app:app"]