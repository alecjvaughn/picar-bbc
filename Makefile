# Use bash for shell commands
SHELL := /bin/bash

# Load configuration from .env file if it exists
-include .env
# Load configuration from .env.local file if it exists (overrides .env)
-include .env.local

# ==============================================================================
# Variables
# ==============================================================================

# Infrastructure
TF_DIR := infrastructure

# Docker Names
SERVER_NAME       := picar-server
CLIENT_NAME       := picar-client
DEBUG_SERVER_NAME := picar-server-debug
TUNNEL_NAME       := picar-tunnel

# Docker Images
ROOT_IMAGE       := local/root_base:latest
MIDDLEWARE_IMAGE := local/python_middleware:latest
SERVER_IMAGE     := local/picar-server:latest
CLIENT_IMAGE     := local/picar-client:latest

# Networking
NETWORK_NAME := picar-net
PORTS        := -p 5050:5050 -p 8080:8080 -p 5001:5001

# Configuration
CLOUDFLARED_TUNNEL_TOKEN ?=
BUILD_ARGS ?=
LOCAL_RASPI_CONNECTION ?=
ANSIBLE_ARGS ?=
REPO_URL ?=
PROJECT_DIR ?=
CLEAN ?= false
TUNNEL_HOSTNAME ?= picar.aleclabs.us
TUNNEL_VIDEO_HOSTNAME ?= picar-video.aleclabs.us

# Tell Ansible where to find the configuration file
export ANSIBLE_CONFIG := ansible/ansible.cfg

# If LOCAL_RASPI_CONNECTION is provided, set DOCKER_HOST for Terraform and Docker CLI
# Also configure Ansible to use this connection instead of inventory.ini
ifneq ($(LOCAL_RASPI_CONNECTION),)
    export DOCKER_HOST := ssh://$(LOCAL_RASPI_CONNECTION)
    ifneq ($(findstring @,$(LOCAL_RASPI_CONNECTION)),)
        ANSIBLE_USER := $(shell echo $(LOCAL_RASPI_CONNECTION) | cut -d@ -f1)
        ANSIBLE_HOST := $(shell echo $(LOCAL_RASPI_CONNECTION) | cut -d@ -f2)
        ANSIBLE_INVENTORY := -i '$(ANSIBLE_HOST),' -u $(ANSIBLE_USER)
    else
        ANSIBLE_INVENTORY := -i '$(LOCAL_RASPI_CONNECTION),'
    endif
    ANSIBLE_TARGET_HOSTS := all
else
    ANSIBLE_INVENTORY :=
    ANSIBLE_TARGET_HOSTS := picar
endif

# ==============================================================================
# Help
# ==============================================================================

.PHONY: help help-all
help:
	@echo "--------------------------------------------------------------------------------"
	@echo "Picar-BBC Makefile - Core Workflow"
	@echo "Run 'make help-all' to see the comprehensive list of all commands."
	@echo "--------------------------------------------------------------------------------"
	@echo "Local Development:"
	@echo "  make run-dev             : Run full local dev stack (Server + API + React Client)"
	@echo "  make test-dev            : Spawn both backend and frontend test runners in new terminals"
	@echo "  make dev-all             : Run local dev stack AND tests simultaneously"
	@echo "  make clean-install       : Wipe and reinstall all Node and Python dependencies"
	@echo "  make clean-terminals     : Manually clean up spawned development terminals/processes"
	@echo ""
	@echo "Deployment & Hardware:"
	@echo "  make ansible-deploy      : Configure the Raspberry Pi and deploy the application"
	@echo '                             (Optional: CLEAN=true or BUILD_ARGS="--build-arg CACHE_BUST=$$(date +%s)")'
	@echo "  make ansible-test        : Run hardware tests via Ansible (COMPONENT=...) [RESTART=true]"
										COMPONENT=<Led|Motor|Ultrasonic|Infrared|Servo|ADC|Buzzer|Camera|Battery|All-Motor|All-Non-Motor|All> [DURATION=60s]
	@echo "  make test-hardware       : Run hardware component tests (stops Python app, keeps container up)"
										COMPONENT=<Led|Motor|Ultrasonic|Infrared|Servo|ADC|Buzzer|Camera|Battery|All-Motor|All-Non-Motor|All> [DURATION=60s]
	@echo "  make logs                : View live server logs from the Pi container"
	@echo ""
	@echo "Remote Access:"
	@echo "  make tunnels             : Open local access to Pi ports via Cloudflare (macOS)"
	@echo "--------------------------------------------------------------------------------"

help-all:
	@echo "--------------------------------------------------------------------------------"
	@echo "Picar-BBC Makefile - Comprehensive Commands"
	@echo "--------------------------------------------------------------------------------"
	@echo "Terraform Workflow (Preferred):"
	@echo "  make up                  : Provision infrastructure (Builds images, starts containers)"
	@echo "                             (Optional: LOCAL_RASPI_CONNECTION=pi@picar.local)"
	@echo "  make down                : Destroy infrastructure"
	@echo "  make reload              : Taint server image and apply (Hot reload)"
	@echo "  make tf-clean            : Clean Terraform state"
	@echo ""
	@echo "Docker Manual Workflow:"
	@echo "  make docker-build        : Build all Docker images"
	@echo "  make docker-rebuild      : Rebuild all Docker images (no cache)"
	@echo "  make docker-up           : Alias for docker-run-server"
	@echo "  make docker-down         : Stop and remove all manual containers"
	@echo "  make docker-run-server   : Run server container manually"
	@echo "  make docker-run-client   : Run client container manually"
	@echo "  make docker-run-tunnel   : Run Cloudflare tunnel (requires CLOUDFLARED_TUNNEL_TOKEN)"
	@echo "  make debug-server        : Run server in foreground"
	@echo "  make docker-prune        : Remove all stopped containers, dangling images, and unused networks"
	@echo "  make logs                : View server logs"
	@echo ""
	@echo "Testing & Hardware Control:"
	@echo "  make test-hardware       : Run hardware component tests (stops Python app, keeps container up)"
	@echo "  make test-exec           : Run hardware tests alongside running Python app (fast, potential conflicts)"
	@echo "  make stop-server-app     : Kill the Python app inside container (keeps container alive)"
	@echo "  make start-server-app    : Start the Python app inside container"
	@echo "  make test-unit           : Run backend API unit tests locally (pytest)"
	@echo "  make test-ui             : Run frontend React unit tests locally (vitest)"
	@echo "  make test-dev            : Spawn both backend and frontend test runners in new terminals"
	@echo "  make dev-all             : Run local dev stack AND tests simultaneously"
	@echo "  make clear-leds          : Manually turn off LEDs (stops Python app)"
	@echo ""
	@echo "Ansible Workflow:"
	@echo "  make ansible-ping        : Ping the Raspberry Pi via Ansible"
	@echo "  make ansible-deploy      : Run the Ansible playbook to configure/deploy"
	@echo '                             (Optional: CLEAN=true to nuke images/cache before deploy)'
	@echo '                             (Optional: BUILD_ARGS="--build-arg CACHE_BUST=$$(date +%s)" to force apt update)'
	@echo "  make ansible-test        : Run hardware tests via Ansible (COMPONENT=...) [RESTART=true]"
	@echo "  make ansible-reboot      : Reboot the Pi and poll for system health"
	@echo "                             (Optional: LOCAL_RASPI_CONNECTION=pi@picar.local or set in .env)"
	@echo "                             (Optional: ANSIBLE_ARGS='-vvv' for debug output)"
	@echo "  make ansible-nuke        : Wipe the project directory on the Pi (Clean Slate)"
	@echo ""
	@echo "Local Development:"
	@echo "  make venv                : Create/Update virtual environment"
	@echo "  make install             : Install dependencies to venv"
	@echo "  make run-server          : Run server locally"
	@echo "  make run-api             : Run FastAPI middleman locally"
	@echo "  make run-dev             : Run full local dev stack (Server + API + React Client)"
	@echo "  make run-client          : Run client locally"
	@echo "  make clean-install       : Clean node_modules (if applicable) and reinstall"
	@echo "  make clean-terminals     : Manually clean up spawned development terminals/processes"
	@echo "  make tunnel-control      : Open local access to remote control port (5050)"
	@echo "  make tunnel-video        : Open local access to remote video port (8080)"
	@echo "  make tunnels             : Spawn both tunnels in new Terminal windows (macOS)"
	@echo "--------------------------------------------------------------------------------"

# ==============================================================================
# Terraform Workflow
# ==============================================================================

.PHONY: tf-init tf-apply tf-destroy up down reload tf-clean ansible-reboot ansible-nuke

tf-init:
	cd $(TF_DIR) && terraform init

up:
	@if grep -q "Raspberry Pi" /sys/firmware/devicetree/base/model 2>/dev/null; then \
		echo "🍓 Raspberry Pi detected. Switching to Docker Manual Workflow (Server Only)..."; \
		$(MAKE) docker-run-server; \
		if [ -n "$(CLOUDFLARED_TUNNEL_TOKEN)" ]; then \
			echo "🚇 Starting Cloudflare Tunnel..."; \
			$(MAKE) docker-run-tunnel; \
		fi; \
	else \
		$(MAKE) tf-apply; \
	fi

tf-apply: tf-init
	@if [ -n "$(LOCAL_RASPI_CONNECTION)" ]; then \
		echo "🚀 Deploying to REMOTE host: $(LOCAL_RASPI_CONNECTION)"; \
	else \
		echo "💻 Deploying to LOCAL host"; \
	fi
	@if [ -z "$(CLOUDFLARED_TUNNEL_TOKEN)" ]; then \
		echo "⚠️  CLOUDFLARED_TUNNEL_TOKEN is not set. Cloudflare Tunnel will be SKIPPED (or destroyed if it exists)."; \
	else \
		echo "✅  CLOUDFLARED_TUNNEL_TOKEN found. Cloudflare Tunnel will be deployed."; \
	fi
	@echo "Ensuring manual container is removed to prevent port conflicts..."
	-docker rm -f $(SERVER_NAME) 2>/dev/null || true
	cd $(TF_DIR) && terraform apply -auto-approve -var="tunnel_token=$(CLOUDFLARED_TUNNEL_TOKEN)"

down:
	@if grep -q "Raspberry Pi" /sys/firmware/devicetree/base/model 2>/dev/null; then \
		echo "🍓 Raspberry Pi detected. Stopping manual containers..."; \
		$(MAKE) docker-down; \
	else \
		$(MAKE) tf-destroy; \
	fi

tf-destroy:
	cd $(TF_DIR) && terraform destroy -auto-approve
	@echo "Cleaning up dangling images and networks..."
	-docker rmi $(SERVER_IMAGE) $(CLIENT_IMAGE) $(MIDDLEWARE_IMAGE) $(ROOT_IMAGE) 2>/dev/null || true
	-docker network rm data_platform_network 2>/dev/null || true

reload:
	cd $(TF_DIR) && terraform taint docker_image.picar_server
	cd $(TF_DIR) && terraform apply -auto-approve

tf-clean:
	rm -rf $(TF_DIR)/.terraform $(TF_DIR)/.terraform.lock.hcl $(TF_DIR)/terraform.tfstate $(TF_DIR)/terraform.tfstate.backup

# ==============================================================================
# Docker Manual Workflow
# ==============================================================================

.PHONY: docker-build docker-build-root docker-build-middleware docker-build-server docker-build-client docker-build-all docker-rebuild create-network docker-run-server debug-server docker-run-client docker-run-tunnel docker-up docker-down docker-clean docker-prune logs

docker-build-root:
	docker build $(BUILD_ARGS) -t $(ROOT_IMAGE) -f docker/images/root/Dockerfile .

docker-build-middleware: docker-build-root
	docker build $(BUILD_ARGS) -t $(MIDDLEWARE_IMAGE) -f docker/images/middleware/Dockerfile .

docker-build-server: docker-build-middleware
	docker build $(BUILD_ARGS) -t $(SERVER_IMAGE) -f docker/images/server/Dockerfile .

docker-build-client:
	docker build $(BUILD_ARGS) -t $(CLIENT_IMAGE) -f docker/images/client/Dockerfile .

docker-build: docker-build-server

docker-build-all: docker-build-server docker-build-client

docker-rebuild:
	$(MAKE) docker-build BUILD_ARGS="--no-cache"

create-network:
	docker network create $(NETWORK_NAME) 2>/dev/null || true

docker-run-server: docker-build create-network
	-docker rm -f $(SERVER_NAME) 2>/dev/null || true
	@# Aggressively kill anything on ports 5050/8080 (use with caution)
	-sudo fuser -k 5050/tcp 2>/dev/null || true
	-sudo fuser -k 8080/tcp 2>/dev/null || true
	-sudo fuser -k 5001/tcp 2>/dev/null || true
	docker run --rm -d --name $(SERVER_NAME) \
		--network $(NETWORK_NAME) \
		--privileged \
		-u root \
		-v /dev/shm:/dev/shm \
		$(PORTS) \
		$(SERVER_IMAGE) \
		/bin/bash -c "python3 main.py --no-gui & python3 WebAPI.py"

debug-server: docker-build
	@echo "Cleaning up old debug container..."
	-docker rm -f $(DEBUG_SERVER_NAME) 2>/dev/null || true
	@echo "Starting server in debug mode (foreground)..."
	docker run --privileged --name $(DEBUG_SERVER_NAME) \
		-u root \
		$(PORTS) \
		$(SERVER_IMAGE)

stop-server-app:
	@echo "🛑 Killing Python server process (Container $(SERVER_NAME) will remain up)..."
	-docker exec -u root $(SERVER_NAME) pkill -f "python3 main.py"

start-server-app:
	@echo "▶️  Starting Python server process in background..."
	docker exec -u root -d $(SERVER_NAME) python3 main.py --no-gui

clear-leds:
	@echo "🧹 Clearing LEDs..."
	$(MAKE) stop-server-app
	docker exec -u root $(SERVER_NAME) python3 test.py Led-Off

docker-run-client: docker-build-client
	@echo "Starting web client on http://localhost:3000..."
	-docker rm -f $(CLIENT_NAME) 2>/dev/null || true
	docker run --rm -d --name $(CLIENT_NAME) \
		-p 3000:80 \
		$(CLIENT_IMAGE)

docker-run-tunnel: docker-build create-network
	@if [ -z "$(CLOUDFLARED_TUNNEL_TOKEN)" ]; then \
		echo "Error: CLOUDFLARED_TUNNEL_TOKEN is not set. Usage: make docker-run-tunnel CLOUDFLARED_TUNNEL_TOKEN=<your-token>"; \
		exit 1; \
	fi
	-docker rm -f $(TUNNEL_NAME) 2>/dev/null || true
	docker run -d --name $(TUNNEL_NAME) --restart unless-stopped \
		--network $(NETWORK_NAME) \
		-e TUNNEL_TOKEN=$(CLOUDFLARED_TUNNEL_TOKEN) \
		$(SERVER_IMAGE) cloudflared tunnel run

docker-up: docker-run-server

docker-down:
	docker stop $(SERVER_NAME) $(CLIENT_NAME) $(DEBUG_SERVER_NAME) $(TUNNEL_NAME) || true
	docker rm $(SERVER_NAME) $(CLIENT_NAME) $(DEBUG_SERVER_NAME) $(TUNNEL_NAME) || true

docker-clean: docker-down
	docker rmi $(SERVER_IMAGE) $(CLIENT_IMAGE) $(MIDDLEWARE_IMAGE) $(ROOT_IMAGE) || true
	@echo "🧹 Clearing Docker BuildKit cache..."
	docker builder prune -a -f

docker-prune: docker-down
	@echo "Pruning all stopped containers, dangling images, and unused networks..."
	docker container prune -f
	docker image prune -f
	docker network prune -f

logs:
	docker logs -f $(SERVER_NAME)

# ==============================================================================
# Testing Workflow
# ==============================================================================

.PHONY: docker-run-test test-hardware test-exec

# Non-interactive test runner for automation/Ansible
docker-run-test:
	docker exec -u root $(SERVER_NAME) \
		/bin/bash -c "timeout --signal=2 $${DURATION:-60s} python3 test.py $(COMPONENT); err=\$$?; if [ \$$err -eq 124 ]; then exit 0; else exit \$$err; fi"

test-hardware:
	@if [ -z "$(COMPONENT)" ]; then \
		echo "Error: COMPONENT argument is required."; \
		echo "Usage: make test-hardware COMPONENT=<Led|Motor|Ultrasonic|Infrared|Servo|ADC|Buzzer|Camera|Battery|All-Motor|All-Non-Motor|All>"; \
		exit 1; \
	fi
	@echo "⚠️  Stopping Python app in $(SERVER_NAME) to free up hardware resources..."
	-$(MAKE) stop-server-app
	@echo "🧪 Running hardware test for $(COMPONENT) inside $(SERVER_NAME)..."
	-docker exec -it -u root $(SERVER_NAME) \
		/bin/bash -c "timeout --signal=2 $${DURATION:-15s} python3 test.py $(COMPONENT); err=\$$?; if [ \$$err -eq 124 ]; then echo -e '\n⏱️  Test finished (Timeout)'; exit 0; else exit \$$err; fi"
	@if [ "$(RESTART)" = "true" ]; then \
		echo "🔄 Restarting Python app in $(SERVER_NAME)..."; \
		$(MAKE) start-server-app; \
	fi

test-exec:
	@if [ -z "$(COMPONENT)" ]; then \
		echo "Error: COMPONENT argument is required."; \
		echo "Usage: make test-exec COMPONENT=<Led|Motor|Ultrasonic|Infrared|Servo|ADC|Buzzer|Camera|Battery|All-Motor|All-Non-Motor|All>"; \
		exit 1; \
	fi
	@echo "⚠️  Running test inside $(SERVER_NAME) alongside the ACTIVE Python app..."
	@echo "    Note: This may conflict with the running Python application (e.g. Camera busy, LEDs overwriting)."
	docker exec -u root -it $(SERVER_NAME) /bin/bash -c "timeout --signal=2 $${DURATION:-15s} python3 test.py $(COMPONENT); err=\$$?; if [ \$$err -eq 124 ]; then echo -e '\n⏱️  Test finished (Timeout)'; exit 0; else exit \$$err; fi"

test-unit:
	@echo "🧪 Running backend unit tests..."
	. venv/bin/activate && pytest src/Server/

test-ui:
	@echo "🧪 Running frontend React tests..."
	npm run test

test-dev:
	@$(MAKE) clean-test
	@echo "🚀 Spawning test runners in separate terminals..."
	@if [ "$$(uname)" = "Darwin" ]; then \
		osascript -e 'tell application "Terminal" to do script "printf \"\\033]0;PiCar Backend Tests\\007\"; cd \"$(CURDIR)\" && make test-unit"'; \
		osascript -e 'tell application "Terminal" to do script "printf \"\\033]0;PiCar Frontend Tests\\007\"; cd \"$(CURDIR)\" && make test-ui"'; \
	else \
		echo "Auto-spawning terminals is only supported on macOS currently."; \
		echo "Please run 'make test-unit' and 'make test-ui' manually."; \
	fi

# ==============================================================================
# Ansible Workflow
# ==============================================================================

.PHONY: ansible-ping ansible-deploy

ansible-ping:
	@echo "📡 Pinging host using inventory: $(if $(ANSIBLE_INVENTORY),$(ANSIBLE_INVENTORY),default (ansible.cfg))"
	ansible $(ANSIBLE_INVENTORY) $(ANSIBLE_TARGET_HOSTS) -m ping $(ANSIBLE_ARGS)

ansible-deploy:
	@echo "🚀 Deploying to host using inventory: $(if $(ANSIBLE_INVENTORY),$(ANSIBLE_INVENTORY),default (ansible.cfg))"
	@if ! command -v ansible-playbook >/dev/null 2>&1; then \
		echo "Error: 'ansible-playbook' is not installed."; \
		echo "  - If running from your computer: Install Ansible (e.g., 'brew install ansible')."; \
		echo "  - If running on the Pi: Install Ansible ('sudo apt install ansible')."; \
		exit 1; \
	fi
	@echo "📦 Phase 1: Provisioning System & Hardware..."
	@ansible-playbook $(ANSIBLE_INVENTORY) ansible/provision.yml \
		-e "target_hosts=$(ANSIBLE_TARGET_HOSTS)" \
		$(if $(CLOUDFLARED_TUNNEL_TOKEN),-e "tunnel_token=$(CLOUDFLARED_TUNNEL_TOKEN)") \
		$(if $(REPO_URL),-e "repo_url=$(REPO_URL)") \
		$(if $(PROJECT_DIR),-e "project_dir=$(PROJECT_DIR)") \
		$(if $(BUILD_ARGS),-e "build_args='$(BUILD_ARGS)'") \
		$(if $(filter true,$(CLEAN)),-e "force_clean=true") \
		$(ANSIBLE_ARGS)
	@echo "🚀 Phase 2: Deploying Application..."
	@ansible-playbook $(ANSIBLE_INVENTORY) ansible/deploy.yml \
		-e "target_hosts=$(ANSIBLE_TARGET_HOSTS)" \
		$(if $(CLOUDFLARED_TUNNEL_TOKEN),-e "tunnel_token=$(CLOUDFLARED_TUNNEL_TOKEN)") \
		$(if $(REPO_URL),-e "repo_url=$(REPO_URL)") \
		$(if $(PROJECT_DIR),-e "project_dir=$(PROJECT_DIR)") \
		$(if $(BUILD_ARGS),-e "build_args='$(BUILD_ARGS)'") \
		$(if $(filter true,$(CLEAN)),-e "force_clean=true") \
		$(ANSIBLE_ARGS)

ansible-test:
	@if [ -z "$(COMPONENT)" ]; then \
		echo "Error: COMPONENT argument is required."; \
		echo "Usage: make ansible-test COMPONENT=<Led|Motor|Ultrasonic|Infrared|Servo|ADC|Buzzer|Camera|Battery|All-Motor|All-Non-Motor|All> [DURATION=60s]"; \
		exit 1; \
	fi
	@echo "🧪 Running hardware test via Ansible for $(COMPONENT)..."
	@ansible-playbook $(ANSIBLE_INVENTORY) ansible/test.yml \
		-e "component=$(COMPONENT)" \
		-e "server_image=$(SERVER_IMAGE)" \
		$(if $(DURATION),-e "test_duration=$(DURATION)") \
		$(if $(RESTART),-e "restart=$(RESTART)") \
		$(if $(PROJECT_DIR),-e "project_dir=$(PROJECT_DIR)") \
		$(ANSIBLE_ARGS)

ansible-reboot:
	@echo "🔄 Rebooting $(ANSIBLE_TARGET_HOSTS) and checking health..."
	@ansible-playbook $(ANSIBLE_INVENTORY) ansible/reboot.yml \
		-e "target_hosts=$(ANSIBLE_TARGET_HOSTS)" \
		$(ANSIBLE_ARGS)

ansible-nuke:
	@echo "☢️  Nuking project directory on $(ANSIBLE_TARGET_HOSTS)..."
	@read -p "Are you sure you want to delete the project directory on the remote host? [y/N] " ans && [ $${ans:-N} = y ]
	@ansible-playbook $(ANSIBLE_INVENTORY) ansible/nuke.yml \
		-e "target_hosts=$(ANSIBLE_TARGET_HOSTS)" \
		$(if $(PROJECT_DIR),-e "project_dir=$(PROJECT_DIR)") \
		$(ANSIBLE_ARGS)

# ==============================================================================
# Local Development
# ==============================================================================

.PHONY: clean-install install rebuild-hardware venv venv-cleanup run-server run-client clean-terminals clean-dev clean-test clean-tunnels dev-all

clean-install:
	rm -rf node_modules package-lock.json
	npm install
	$(MAKE) venv-cleanup
	$(MAKE) venv
	. venv/bin/activate

install:
	@echo "Installing requirements into venv..."
	@. venv/bin/activate && pip install --upgrade pip
	@if grep -q "Raspberry Pi" /sys/firmware/devicetree/base/model 2>/dev/null; then \
		echo "Raspberry Pi detected. Installing requirements, excluding those provided by apt..."; \
		grep -v -e "numpy" -e "gpiozero" -e "opencv-python-headless" src/requirements.txt > requirements.tmp; \
		. venv/bin/activate && pip install -r requirements.tmp; \
		rm requirements.tmp; \
	else \
		echo "Non-RPi OS detected. Installing requirements (excluding hardware libs)..."; \
		grep -v -e "rpi-ws281x" -e "rpi-lgpio" src/requirements.txt > requirements.tmp; \
		. venv/bin/activate && pip install -r requirements.tmp; \
		rm requirements.tmp; \
	fi

rebuild-hardware:
	@echo "Rebuilding hardware-specific libraries..."
	@. venv/bin/activate && pip install --force-reinstall --no-cache-dir rpi-ws281x || echo "Warning: rpi-ws281x failed to build. Using mocks."

venv:
	@if grep -q "Raspberry Pi" /sys/firmware/devicetree/base/model 2>/dev/null; then \
		echo "Raspberry Pi detected. Installing system dependencies..."; \
		sudo apt-get update && sudo apt-get install -y python3-dev python3-numpy python3-gpiozero python3-opencv libcamera-tools gstreamer1.0-libcamera gstreamer1.0-plugins-base gstreamer1.0-plugins-good; \
		test -d venv || python3 -m venv venv --system-site-packages; \
	else \
		test -d venv || python3 -m venv venv; \
	fi
	@$(MAKE) install
	@echo "Virtual environment ready. Activate with: source venv/bin/activate"

venv-cleanup:
	rm -rf venv
	@echo "Virtual environment removed."

run-server:
	. venv/bin/activate && python3 src/Server/main.py --no-gui

run-api:
	. venv/bin/activate && python3 src/Server/WebAPI.py

clean-terminals:
	@echo "🧹 Cleaning up previously spawned terminals and processes..."
	@-pkill -f "python3 src/Server/main.py" 2>/dev/null || true
	@-pkill -f "python3 src/Server/WebAPI.py" 2>/dev/null || true
	@-pkill -f "vite src" 2>/dev/null || true
	@-pkill -f "cloudflared access tcp" 2>/dev/null || true
	@-pkill -f "pytest" 2>/dev/null || true
	@-pkill -f "vitest" 2>/dev/null || true
	@if [ "$$(uname)" = "Darwin" ]; then \
		osascript -e 'tell application "Terminal" to close (every window whose name contains "PiCar Server")' 2>/dev/null || true; \
		osascript -e 'tell application "Terminal" to close (every window whose name contains "PiCar API")' 2>/dev/null || true; \
		osascript -e 'tell application "Terminal" to close (every window whose name contains "PiCar React")' 2>/dev/null || true; \
		osascript -e 'tell application "Terminal" to close (every window whose name contains "PiCar Control Tunnel")' 2>/dev/null || true; \
		osascript -e 'tell application "Terminal" to close (every window whose name contains "PiCar Video Tunnel")' 2>/dev/null || true; \
		osascript -e 'tell application "Terminal" to close (every window whose name contains "PiCar Backend Tests")' 2>/dev/null || true; \
		osascript -e 'tell application "Terminal" to close (every window whose name contains "PiCar Frontend Tests")' 2>/dev/null || true; \
	fi

run-dev:
	@$(MAKE) clean-terminals
	@echo "🚀 Spawning full local development stack in separate terminals..."
	@if [ "$$(uname)" = "Darwin" ]; then \
		osascript -e 'tell application "Terminal" to do script "printf \"\\033]0;PiCar Server\\007\"; cd \"$(CURDIR)\" && make run-server"'; \
		osascript -e 'tell application "Terminal" to do script "printf \"\\033]0;PiCar API\\007\"; cd \"$(CURDIR)\" && make run-api"'; \
		osascript -e 'tell application "Terminal" to do script "printf \"\\033]0;PiCar React\\007\"; cd \"$(CURDIR)\" && npm run dev"'; \
	else \
		echo "Auto-spawning terminals is only supported on macOS currently."; \
		echo "Please run 'make run-server', 'make run-api', and 'npm run dev' manually."; \
	fi

run-client:
	. venv/bin/activate && python3 src/Client/Qt/Main.py

tunnel-control:
	@echo "Opening control tunnel to $(TUNNEL_HOSTNAME) on localhost:5050..."
	cloudflared access tcp --hostname $(TUNNEL_HOSTNAME) --url localhost:5050

tunnel-video:
	@echo "Opening video tunnel to $(TUNNEL_VIDEO_HOSTNAME) on localhost:8080..."
	cloudflared access tcp --hostname $(TUNNEL_VIDEO_HOSTNAME) --url localhost:8080

tunnels:
	@$(MAKE) clean-tunnels
	@echo "Spawning tunnels in separate terminals..."
	@if [ "$$(uname)" = "Darwin" ]; then \
		osascript -e 'tell application "Terminal" to do script "printf \"\\033]0;PiCar Control Tunnel\\007\"; cd \"$(CURDIR)\" && make tunnel-control"'; \
		osascript -e 'tell application "Terminal" to do script "printf \"\\033]0;PiCar Video Tunnel\\007\"; cd \"$(CURDIR)\" && make tunnel-video"'; \
	else \
		echo "Auto-spawning terminals is only supported on macOS currently."; \
		echo "Please run 'make tunnel-control' and 'make tunnel-video' in separate terminals manually."; \
	fi

dev-all:
	@$(MAKE) run-dev
	@$(MAKE) test-dev