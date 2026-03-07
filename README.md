# Picar-BBC: Freenove 4WD Smart Car Controller

This project provides a client-server architecture for controlling the Freenove 4WD Smart Car Kit for Raspberry Pi. It features a Python-based server that runs on the Raspberry Pi to interface with hardware (GPIO, Camera, Motors, LEDs) and a PyQt5-based client for remote control and video streaming.

## Features

- **Remote Control**: Control motors and servos via TCP/IP.
- **Video Streaming**: Real-time camera feed from the Raspberry Pi.
- **Sensor Data**: Read ultrasonic distance, light levels, and line tracking sensors.
- **LED Control**: Control WS2812B LEDs with various animation modes.
- **Dockerized**: Easy deployment using Docker for both client and server.
- **Cross-Platform**: Client runs on macOS, Linux, and Windows.

## Prerequisites

- **Hardware**: Raspberry Pi (3, 4, or 5) with Freenove 4WD Smart Car Kit.
- **Software**:
  - Docker Desktop (or Docker Engine on Linux).
  - `make` (for build automation).
  - **macOS Users**: XQuartz is required for the GUI client in Docker.

## Quick Start (Docker)

The easiest way to run the application is using the provided `Makefile` and Docker.

### 1. Run the Server
The server manages the hardware. On the Raspberry Pi (or for testing with mocks on PC):

```bash
make docker-run-server
```

This starts the server on ports `5000` (Command) and `8000` (Video).

### 2. Run the Client
The client provides the GUI. On your control computer:

```bash
make docker-run-client
```

**Note for macOS**: The Makefile attempts to configure X11 forwarding automatically. Ensure XQuartz is running and "Allow connections from network clients" is enabled in XQuartz settings.

### 3. Remote Access (Cloudflare Tunnel)
To securely access the robot from outside your local network without opening ports:

1.  Obtain a **Tunnel Token** from the Cloudflare Zero Trust Dashboard.
2.  Run the tunnel container:

```bash
make docker-run-tunnel CLOUDFLARED_TUNNEL_TOKEN=eyJhIjoi...
```

## Local Development

If you prefer to run without Docker (e.g., for direct hardware access on the Pi or development):

1.  **Create Virtual Environment**:
    ```bash
    make venv
    ```

2.  **Run Server**:
    ```bash
    make run-server
    ```

3.  **Run Client**:
    ```bash
    make run-client
    ```

## Project Structure

- **`src/Client/`**: PyQt5 GUI application code.
- **`src/Server/`**: Python code for controlling Raspberry Pi hardware (GPIO, Camera, etc.).
- **`src/Libs/`**: Custom libraries (e.g., `rpi_ws281x`).
- **`docker/`**: Dockerfiles for Root, Middleware, Server, and Client images.
- **`infrastructure/`**: Terraform configuration for local Docker resource management.

## Cloudflare Tunnel Implementation

To enable secure remote access without opening firewall ports, this project integrates Cloudflare Tunnel.

- **Integration**: The `cloudflared` binary is installed in the `python_middleware` Docker image, making it available in all derived images.
- **Architecture**: The tunnel runs in a dedicated container (`picar-tunnel`) alongside the server container (`picar-server`) on the shared Docker network (`picar-net`).
- **Configuration**:
  - The tunnel authenticates using a token provided via the `CLOUDFLARED_TUNNEL_TOKEN` environment variable.
  - In the Cloudflare Dashboard, configure the tunnel service to point to `http://picar-server:8000`.

## Troubleshooting

- **Client GUI not showing (macOS)**:
    - Install XQuartz: `brew install --cask xquartz`
    - Log out and log back in.
    - Enable "Allow connections from network clients" in XQuartz > Preferences > Security.
    - Run `xhost +localhost` manually if the Makefile step fails.

- **GPIO Errors**:
    - If running locally on a non-Raspberry Pi machine, the code uses mocks.
    - If running in Docker on a Mac (M1/M2), the server detects the container environment and forces mocks to prevent crashes.
