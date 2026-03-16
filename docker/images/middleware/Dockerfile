# PSEUDOCODE: Python Middleware
# 1. Inherit from the secure Root Image (Local build context)
FROM local/root_base:latest AS python_middleware

# 2. Install Runtime Dependencies
# Install Python 3, pip, and venv (standard for Debian 12+)
RUN apt-get update && apt-get install -y --no-install-recommends \
    # System & Build Tools
    build-essential \
    ca-certificates \
    curl \
    procps \
    # Python Core
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    # Hardware & GPIO
    i2c-tools \
    python3-lgpio \
    python3-rpi-lgpio \
    python3-smbus \
    python3-spidev \
    # GUI & Display (Qt/X11)
    libgl1-mesa-glx \
    libglib2.0-0 \
    libx11-xcb1 \
    libxcb-cursor0 \
    libxcb-xinerama0 \
    libxkbcommon-x11-0 \
    python3-pyqt5 \
    qt5-qmake \
    qtbase5-dev \
    # Python Science/Image
    python3-opencv \
    python3-numpy \
    python3-pil \
    # GStreamer & Libcamera
    libcamera-tools \
    gstreamer1.0-libcamera \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    && curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$(dpkg --print-architecture).deb \
    && dpkg -i cloudflared.deb \
    && rm cloudflared.deb \
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