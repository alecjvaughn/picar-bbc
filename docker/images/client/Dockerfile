# PSEUDOCODE: Application Image
# 1. Inherit from the Python Middleware
FROM local/python_middleware:latest AS app_client

WORKDIR /app

# 2. Dependency Caching Layer
# Copy only requirements first. Docker caches this layer if the file hasn't changed.
COPY --chown=secureuser:pipeline src/requirements.txt .

# 3. Install Libraries
RUN grep -v -e "PyQt5" -e "opencv-python-headless" requirements.txt > requirements.tmp && pip install --no-cache-dir -r requirements.tmp && rm requirements.tmp

# 4. Application Logic
COPY --chown=secureuser:pipeline src/ .

# 5. Runtime Configuration
WORKDIR /app/Client
CMD ["python3", "Qt/Main.py"]