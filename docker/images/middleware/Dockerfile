# PSEUDOCODE: Python Middleware
# 1. Inherit from the secure Root Image (Local build context)
FROM local/root_base:latest AS python_middleware

# 2. Install Runtime Dependencies
# Install Python 3, pip, and venv (standard for Debian 12+)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# 3. Environment Configuration
# Prevent Python from writing .pyc files and buffering stdout (best for logs)
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# 4. Set up Virtual Environment
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# 5. Security Handoff
# Ensure the secure user owns the virtual environment
RUN chown -R secureuser:pipeline /opt/venv
USER secureuser