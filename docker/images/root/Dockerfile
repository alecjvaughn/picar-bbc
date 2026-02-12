# PSEUDOCODE: Root Image
# 1. Start with the requested Debian OS (Slim for container efficiency)
FROM debian:bookworm-slim AS root_base

# 2. System Hardening & Updates
# Update package lists and upgrade existing packages to fix CVEs
RUN apt-get update && apt-get upgrade -y && \
    # Install essential security certificates (needed for HTTPS/API calls)
    apt-get install -y --no-install-recommends ca-certificates curl && \
    # Clean up apt cache to keep image small
    rm -rf /var/lib/apt/lists/*

# 3. Identity Management (Zero Trust)
# Create a dedicated non-root user/group to run the application
RUN groupadd -r pipeline && useradd -r -g pipeline secureuser

# 4. Set global working directory
WORKDIR /app