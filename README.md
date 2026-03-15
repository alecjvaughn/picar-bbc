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
  - `terraform` (Optional: Can be installed on your computer instead of the Pi).
  - **macOS Users**: XQuartz is required for the GUI client in Docker.

## Raspberry Pi Setup (From Scratch)

If you are setting up a new Raspberry Pi for this project, follow these steps:

### 1. Install Operating System
1.  Use Raspberry Pi Imager to flash **Raspberry Pi OS (64-bit)** (Bookworm or later) to your SD card.
2.  In the Imager settings (gear icon), configure:
    -   **Hostname**: `picar`
    -   **SSH**: Enable with password authentication.
    -   **Wi-Fi**: Enter your SSID and password.
    -   **Username/Password**: Create your user (e.g., `pi`).

### 2. Initial Configuration
Boot the Pi and SSH into it:
```bash
ssh pi@picar.local
```

Update the system and enable necessary hardware interfaces:
```bash
sudo apt update && sudo apt full-upgrade -y
sudo raspi-config
```
Navigate to **Interface Options** and enable:
*   **SPI** (Required for LEDs/Motors)
*   **I2C** (Required for Sensors)
*   **Camera** (If using the camera module)

Reboot the Pi:
```bash
sudo reboot
```

### 3. Install Dependencies
Install Docker, Git, and Make:

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Git and Make
sudo apt install -y git make

**Log out and log back in** to apply the Docker group changes.

### 4. Automated Setup (Ansible)
Alternatively, you can use Ansible to automate the setup and deployment from your computer.

**Note**: Ansible is **agentless**. You do NOT need to install Ansible on the Raspberry Pi. It only needs to be installed on your computer (Control Node).

1.  Install Ansible on your control computer.
2.  Run the deployment via Make:

    ```bash
    # Option A: Use LOCAL_RASPI_CONNECTION (Recommended)
    # If defined in .env, simply run:
    make ansible-deploy

    # If your Pi user requires a password for sudo (default), ask Ansible to prompt for it:
    make ansible-deploy ANSIBLE_ARGS="-K"
    # (SSH keys handle login, but administrative tasks via 'sudo' still require a password by default)

    # Or pass it inline:
    make ansible-deploy LOCAL_RASPI_CONNECTION=pi@picar.local

    # Option B: Use inventory.ini
    # Edit ansible/inventory.ini first, then run:
    make ansible-deploy
    
    # With Cloudflare Tunnel
    # Set CLOUDFLARED_TUNNEL_TOKEN in .env or export it:
    make ansible-deploy
    ```

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

## Remote Deployment (Advanced)

You can run Terraform and Make on your computer and deploy to the Pi remotely. This allows you to keep your Pi clean (only Docker required) and run all build/deploy commands (`make up`) from your computer.

1.  **Configure SSH**: Ensure you can SSH into the Pi without a password (use SSH keys).
    ```bash
    ssh-copy-id pi@picar.local
    ```
2.  **Deploy**:
    
    You can pass the connection string directly:

    ```bash
    make up LOCAL_RASPI_CONNECTION=pi@picar.local
    ```
    
    **Or** create a `.env` file in the project root to save it:
    ```bash
    echo "LOCAL_RASPI_CONNECTION=pi@picar.local" > .env
    make up
    ```

This sends the build context to the Pi, builds images on the Pi, and starts containers on the Pi.

### How this works
1.  **`LOCAL_RASPI_CONNECTION`**: The Makefile sets `DOCKER_HOST` based on this variable.
2.  **`DOCKER_HOST`**: This environment variable tells both the `docker` CLI and Terraform (via the `kreuzwerker/docker` provider) to execute commands on the remote machine instead of your local one.
3.  **Terraform**: When you run `make up` locally, Terraform zips your source code, sends it to the Pi's Docker daemon, builds the images *on the Pi* (ensuring the correct ARM architecture), and starts the containers *on the Pi*.

### Summary of what you can remove from the Pi
*   ✅ **Terraform**: Safe to remove.
*   ✅ **Source Code**: Safe to remove (if deploying remotely, the context is sent during build).
*   ❌ **Docker**: **Must keep.** It is the engine running your robot.

## Connecting to the Server

Based on your project configuration, there are two main ways to reach your picar-server, depending on whether you are on the same Wi-Fi network or connecting remotely.

### 1. Local Network Access (Same Wi-Fi)
If your computer and the Raspberry Pi are on the same network, you can connect directly using the Pi's IP address or hostname.

- **Hostname**: `picar.local` (Assuming you followed the README setup)
- **Control Port (TCP)**: `5000`
- **Video Stream (MJPEG)**: `8000`

**URLs**:
- Control API: `http://picar.local:5000`
- Video Feed: `http://picar.local:8000`

*(If `picar.local` doesn't work, find your Pi's IP address using `hostname -I` on the Pi and use that instead, e.g., `http://192.168.1.15:5000`)*

### 2. Remote Access (Cloudflare Tunnel)
If you have deployed the Cloudflare Tunnel using `make docker-run-tunnel` or `make up`, you can access the robot from anywhere on the internet without being on the same Wi-Fi.

- **URL**: This is the Public Hostname you configured in your Cloudflare Zero Trust Dashboard (e.g., `https://robot.yourdomain.com`).
- **Configuration**: Ensure your Cloudflare Tunnel "Service" is pointing to `http://picar-server:8000` (for video) or `http://picar-server:5000` (for control) inside the dashboard settings.

### 3. Using the Client Application
To control the robot using the desktop GUI client:

1.  Run the client on your computer:
    ```bash
    make run-client
    # OR if you don't have Python installed locally:
    make docker-run-client
    ```
2.  In the client interface, look for the **IP/Host** field.
    -   **Local**: Enter `picar.local` or the IP address.
    -   **Remote**: Enter your Cloudflare domain (e.g., `robot.yourdomain.com`).

## Hardware Testing

The project includes a test suite to verify individual hardware components. This is useful for debugging wiring or sensor issues.

### Available Components
- **`Led`**: Cycles through RGB colors on the WS2812B strip.
- **`Motor`**: Tests forward, backward, left, right, and stop.
- **`Ultrasonic`**: Prints distance readings (cm).
- **`Infrared`**: Prints line tracking sensor status (Left, Middle, Right).
- **`Servo`**: Sweeps camera servos (pan/tilt).
- **`ADC`**: Reads battery voltage and photoresistor values.
- **`Battery`**: Reads battery voltage only.
- **`Buzzer`**: Beeps for 3 seconds.
- **`Camera`**: Tests initialization and captures a test image (`test_camera.jpg`).

### 1. Manual Testing (On the Pi)
If you are SSH'd into the Pi, you can run tests using Docker. This will temporarily stop the main server to free up hardware resources.

```bash
make test-hardware COMPONENT=Led
```

### 2. Remote Testing (Ansible)
You can trigger tests from your control computer without SSHing into the Pi.

```bash
make ansible-test COMPONENT=Servo RESTART=true
```

## Project Structure

- **`src/Client/`**: PyQt5 GUI application code.
- **`src/Server/`**: Python code for controlling Raspberry Pi hardware (GPIO, Camera, etc.).
- **`src/Libs/`**: Custom libraries (e.g., `rpi_ws281x`).
- **`docker/`**: Dockerfiles for Root, Middleware, Server, and Client images.
- **`infrastructure/`**: Terraform configuration for local Docker resource management.
- **`ansible/`**: Ansible playbooks for automated Raspberry Pi configuration and deployment.

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
