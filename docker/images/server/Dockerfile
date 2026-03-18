# PSEUDOCODE: Application Image
# 1. Inherit from the Python Middleware
FROM local/python_middleware:latest AS app_server

WORKDIR /app

# 2. Dependency Caching Layer
# Copy only requirements first. Docker caches this layer if the file hasn't changed.
COPY --chown=secureuser:pipeline src/requirements.txt .

# 3. Install Libraries
RUN grep -v -e "opencv-python-headless" requirements.txt > requirements.tmp && pip install --no-cache-dir -r requirements.tmp && rm requirements.tmp

# 4. Application Logic
COPY --chown=secureuser:pipeline docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
COPY --chown=secureuser:pipeline src/Server /app/Server
# COPY --chown=secureuser:pipeline src/Libs /app/Libs
# Lib dependencies are installed via --system-site-packages in the virtual environment, so we don't need to copy them here. This keeps the image smaller and leverages Debian's package management for security updates.

# 5. Runtime Configuration
EXPOSE 5050
EXPOSE 8080
EXPOSE 5001

# 6. Runtime Configuration
ENTRYPOINT ["docker-entrypoint.sh"]