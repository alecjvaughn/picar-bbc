# PSEUDOCODE: Application Image
# 1. Inherit from the Python Middleware
FROM local/python_middleware:latest AS app_server

WORKDIR /app

# 2. Dependency Caching Layer
# Copy only requirements first. Docker caches this layer if the file hasn't changed.
COPY --chown=secureuser:pipeline src/requirements.txt .

# 3. Install Libraries
RUN pip install --no-cache-dir -r requirements.txt

# 4. Application Logic
COPY --chown=secureuser:pipeline src/ .

# 5. Runtime Configuration
EXPOSE 5000
EXPOSE 8000

# 6. Runtime Configuration
ENV QT_QPA_PLATFORM=offscreen
WORKDIR /app/Server
CMD ["python3", "main.py", "--no-gui"]