# Picar-BBC: Freenove 4WD Smart Car Controller

This project provides a client-server architecture for controlling the Freenove 4WD Smart Car Kit for Raspberry Pi. It features a Python-based server that runs on the Raspberry Pi to interface with hardware (GPIO, Camera, Motors, LEDs) and a web-based client for remote control and video streaming.

## Features

- **Remote Control**: Control motors and servos via TCP/IP.
- **Video Streaming**: Real-time camera feed from the Raspberry Pi.
- **Web Interface**: Modern, responsive UI for control and streaming, accessible from any browser.
- **Sensor Data**: Read ultrasonic distance, light levels, and line tracking sensors.
- **LED Control**: Control WS2812B LEDs with various animation modes.
- **Dockerized**: Easy deployment using Docker for both client and server.
- **Ansible Deployment**: Fully automated setup and deployment to the Raspberry Pi.

## Prerequisites

- **Hardware**: Raspberry Pi (3, 4, or 5) with Freenove 4WD Smart Car Kit.
- **Software**:
  - Docker Desktop (or Docker Engine on Linux).
  - `make` (for build automation).
  - `ansible` (Required on your control computer).

## Setup and Deployment

If you are setting up a new Raspberry Pi for this project, follow these steps:

### 1. Install Operating System
1.  Use Raspberry Pi Imager to flash **Raspberry Pi OS (64-bit)** to your SD card.
    *   **⚠️ CRITICAL OS NOTE:** You must select the **Debian 12 "Bookworm" (64-bit)** release. Do *not* use the 32-bit version, and do *not* use the newer "Trixie" testing release. The `picamera2` library and Docker configuration used in this project are strictly bound to the Bookworm kernel. (In the Imager, look under "Raspberry Pi OS (Other)" to find the Bookworm 64-bit image).
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

### 4. Deploy from Your Computer
The recommended way to deploy the application is using Ansible from your control computer. This automates the entire process, from setting system dependencies to building and running the Docker containers on the Pi.

**Note**: Ansible is **agentless**. It only needs to be installed on your computer (the "Control Node"), not on the Raspberry Pi itself.

1.  **Clone the Repository** on your control computer.
    ```bash
    git clone https://github.com/your-username/picar-bbc.git
    cd picar-bbc
    ```
1.  Install Ansible on your control computer.
    - macOS: `brew install ansible`
    - Other: See Ansible installation guide.

2.  **Configure Connection**: Create a `.env` file in the project root to tell Make and Ansible how to connect to your Pi.
    ```bash
    echo "LOCAL_RASPI_CONNECTION=pi@picar.local" > .env
    ```
    *(This ensures you don't have to pass the connection string to every command.)*

3.  **Deploy**: Run the main deployment command from your computer.

    ```bash
    make deploy

    # If your Pi user requires a password for sudo (default), ask Ansible to prompt for it:
    make deploy ANSIBLE_ARGS="-K"
    # (SSH keys handle login, but administrative tasks via 'sudo' still require a password by default)
    ```

That's it! The `make deploy` command handles everything. The server will be running on the Pi, exposing ports `5050` (API) and `8080` (Video).

#### Deploying Branches or Forcing Rebuilds
To deploy a specific branch or force a clean rebuild, you can pass variables to the command:
```bash
# Deploy a feature branch
make deploy BRANCH=my-feature-branch

# Force a clean build (no Docker cache)
make deploy CLEAN=true
```

## Running the Application

The `make deploy` command starts the server on the Pi. To control the robot, you run the web client on your computer.

### Run the Web Client

#### Option A: Run with Docker (Recommended)
This is the easiest method and doesn't require installing Node.js or Python locally.
```bash
make docker-run-client
```
This will start a web server. Open your browser to **`http://localhost:3000`**.

#### Option B: Run for Local Development
If you want to modify the client code, you can run it in a local development environment.
```bash
make run-dev
```
This will start the backend server (with mocks), the API, and the React development server.

## Connecting to the Server

Based on your project configuration, there are two main ways to reach your picar-server, depending on whether you are on the same Wi-Fi network or connecting remotely.

### 1. Local Network Access (Same Wi-Fi)
If your computer and the Raspberry Pi are on the same network, you can connect directly using the Pi's IP address or hostname.

- **Hostname**: `picar.local` (Assuming you followed the README setup)
- **Control Port (TCP)**: `5000`
- **Web API Port**: `5001`

**URLs**:
- Control API: `http://picar.local:5001/api/`
- Video Feed: `http://picar.local:5001/api/video_feed`

*(If `picar.local` doesn't work, find your Pi's IP address using `hostname -I` on the Pi and use that instead, e.g., `http://192.168.1.15:5001`)*

### 2. Remote Access (Cloudflare Tunnel)
If you have deployed with a Cloudflare Tunnel token, you can access the robot from anywhere on the internet.

- **URL**: This is the Public Hostname you configured in your Cloudflare Zero Trust Dashboard (e.g., `https://robot.yourdomain.com`).
- **Configuration**: The Ansible playbook automatically configures the tunnel. Ensure your Cloudflare Tunnel "Service" points to `http://picar-server:5001` to access the Web API and video stream.

### 3. Using the Web Client
To control the robot using the web interface:

1.  Run the client on your computer (see "Run the Web Client" section above).
    ```bash
    make docker-run-client
    ```
2.  Open your browser to `http://localhost:3000`.
3.  In the web interface's settings, enter the address of your robot.
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

### 1. Remote Testing (from your computer)
The primary way to test hardware is from your control computer. This command stops the main application on the Pi, runs the specified test, and then restarts the application.

```bash
make test COMPONENT=Servo
```

### 2. On-Pi Testing (when SSH'd into the Pi)
If you are logged into the Pi directly, you can use `test-hardware` for a more interactive experience.

```bash
make test-hardware COMPONENT=Led RESTART=true
```

## Project Structure

- **`src/Client/`**: React-based web application code.
- **`src/Server/`**: Python code for controlling Raspberry Pi hardware (GPIO, Camera, etc.).
- **`src/Libs/`**: Custom libraries (e.g., `rpi_ws281x`).
- **`docker/`**: Dockerfiles for Root, Middleware, Server, and Client images.
- **`infrastructure/`**: Terraform configuration for local Docker resource management.
- **`ansible/`**: Ansible playbooks for automated Raspberry Pi configuration and deployment.

## Troubleshooting

- **Application is stuck or unresponsive on the Pi**:
    - If the Docker containers on the Pi are in a bad state, you can force a clean redeployment from your computer. This command will forcefully stop all project-related containers before starting a fresh deployment.
    - `make redeploy`
- **`make deploy` fails with permission errors**:
    - Ensure your user on the Pi is in the `docker` group (`sudo usermod -aG docker $USER`).
    - If your user requires a password for `sudo`, use `make deploy ANSIBLE_ARGS="-K"`.
- **`picar.local` not resolving**:
    - Ensure your computer and the Pi are on the same Wi-Fi network.
    - Find the Pi's IP with `hostname -I` on the Pi and use it directly.

- **GPIO Errors**:
    - If running locally on a non-Raspberry Pi machine, the code uses mocks.
    - If running in Docker on a Mac (M1/M2), the server detects the container environment and forces mocks to prevent crashes.
