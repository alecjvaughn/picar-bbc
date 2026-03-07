# PSEUDOCODE: Python Middleware
# 1. Inherit from the secure Root Image (Local build context)
FROM local/root_base:latest AS python_middleware

# 2. Install Runtime Dependencies
# Install Python 3, pip, and venv (standard for Debian 12+)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    python3-pyqt5 \
    qtbase5-dev \
    qt5-qmake \
    python3-numpy \
    python3-pil \
    libx11-xcb1 \
    libxcb-xinerama0 \
    libxkbcommon-x11-0 \
    libxcb-cursor0 \
    libgl1-mesa-glx \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# 3. Environment Configuration
# Prevent Python from writing .pyc files and buffering stdout (best for logs)
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV CONTAINER=true

# 4. Set up Virtual Environment
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV --system-site-packages
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# 5. Security Handoff
# Ensure the secure user owns the virtual environment
RUN chown -R secureuser:pipeline /opt/venv
USER secureuser