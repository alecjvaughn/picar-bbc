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
PORTS        := -p 5000:5000 -p 8000:8000

# Configuration
CLOUDFLARED_TUNNEL_TOKEN ?=
BUILD_ARGS ?=
LOCAL_RASPI_CONNECTION ?=
ANSIBLE_ARGS ?=
REPO_URL ?=
PROJECT_DIR ?=
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

.PHONY: help
help:
	@echo "--------------------------------------------------------------------------------"
	@echo "Picar-BBC Makefile"
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
	@echo "  make test-hardware       : Run hardware component tests (stops server)"
	@echo "  make docker-prune        : Remove all stopped containers, dangling images, and unused networks"
	@echo "  make logs                : View server logs"
	@echo ""
	@echo "Ansible Workflow:"
	@echo "  make ansible-ping        : Ping the Raspberry Pi via Ansible"
	@echo "  make ansible-deploy      : Run the Ansible playbook to configure/deploy"
	@echo "  make ansible-test        : Run hardware tests via Ansible (COMPONENT=...) [RESTART=true]"
	@echo "                             (Optional: LOCAL_RASPI_CONNECTION=pi@picar.local or set in .env)"
	@echo "                             (Optional: ANSIBLE_ARGS='-vvv' for debug output)"
	@echo ""
	@echo "Local Development:"
	@echo "  make venv                : Create/Update virtual environment"
	@echo "  make install             : Install dependencies to venv"
	@echo "  make run-server          : Run server locally"
	@echo "  make run-client          : Run client locally"
	@echo "  make clean-install       : Clean node_modules (if applicable) and reinstall"
	@echo "  make tunnel-control      : Open local access to remote control port (5000)"
	@echo "  make tunnel-video        : Open local access to remote video port (8000)"
	@echo "  make tunnels             : Spawn both tunnels in new Terminal windows (macOS)"
	@echo "--------------------------------------------------------------------------------"

# ==============================================================================
# Terraform Workflow
# ==============================================================================

.PHONY: tf-init tf-apply tf-destroy up down reload tf-clean

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

.PHONY: docker-build docker-build-root docker-build-middleware docker-build-server docker-build-client docker-build-all docker-rebuild create-network docker-run-server debug-server x11-setup docker-run-client docker-run-tunnel docker-run-test docker-up docker-down docker-clean docker-prune logs

docker-build-root:
	docker build $(BUILD_ARGS) -t $(ROOT_IMAGE) -f docker/images/root/Dockerfile .

docker-build-middleware: docker-build-root
	docker build $(BUILD_ARGS) -t $(MIDDLEWARE_IMAGE) -f docker/images/middleware/Dockerfile .

docker-build-server: docker-build-middleware
	docker build $(BUILD_ARGS) -t $(SERVER_IMAGE) -f docker/images/server/Dockerfile .

docker-build-client: docker-build-middleware
	docker build $(BUILD_ARGS) -t $(CLIENT_IMAGE) -f docker/images/client/Dockerfile .

docker-build: docker-build-server

docker-build-all: docker-build-server docker-build-client

docker-rebuild:
	$(MAKE) docker-build BUILD_ARGS="--no-cache"

create-network:
	docker network create $(NETWORK_NAME) 2>/dev/null || true

docker-run-server: docker-build create-network
	-docker rm -f $(SERVER_NAME) 2>/dev/null || true
	@# Aggressively kill anything on port 5000 (use with caution)
	-sudo fuser -k 5000/tcp 2>/dev/null || true
	docker run --rm -d --name $(SERVER_NAME) \
		--network $(NETWORK_NAME) \
		--privileged \
		-u root \
		$(PORTS) \
		$(SERVER_IMAGE)

debug-server: docker-build
	@echo "Cleaning up old debug container..."
	-docker rm -f $(DEBUG_SERVER_NAME) 2>/dev/null || true
	@echo "Starting server in debug mode (foreground)..."
	docker run --privileged --name $(DEBUG_SERVER_NAME) \
		-u root \
		$(PORTS) \
		$(SERVER_IMAGE)

# Non-interactive test runner for automation/Ansible
docker-run-test:
	docker run --rm --privileged \
		-u root \
		--device /dev/i2c-1 \
		--device /dev/spidev0.0 \
		--device /dev/spidev0.1 \
		-v /run/udev:/run/udev:ro \
		-v /tmp:/tmp \
		$(SERVER_IMAGE) \
		python test.py $(COMPONENT)

test-hardware:
	@if [ -z "$(COMPONENT)" ]; then \
		echo "Error: COMPONENT argument is required."; \
		echo "Usage: make test-hardware COMPONENT=<Led|Motor|Ultrasonic|Infrared|Servo|ADC|Buzzer|Camera|Battery|Motor-All|Non-Motor-All>"; \
		exit 1; \
	fi
	@echo "⚠️  Stopping $(SERVER_NAME) to free up hardware resources..."
	-docker stop $(SERVER_NAME) 2>/dev/null || true
	@echo "🧪 Running hardware test for $(COMPONENT)..."
	docker run --rm -it --privileged \
		-u root \
		--device /dev/i2c-1 \
		--device /dev/spidev0.0 \
		--device /dev/spidev0.1 \
		-v /run/udev:/run/udev:ro \
		-v /tmp:/tmp \
		$(SERVER_IMAGE) \
		python test.py $(COMPONENT)
	@if [ "$(RESTART)" = "true" ]; then \
		echo "🔄 Restarting $(SERVER_NAME)..."; \
		$(MAKE) docker-run-server; \
	fi

x11-setup:
	@echo "Configuring X11..."
	@if [ "$$(uname)" = "Darwin" ]; then \
		echo "Configuring X11 for macOS..."; \
		echo "Ensure XQuartz is running and 'Allow connections from network clients' is checked in Preferences > Security."; \
		open -a XQuartz || echo "Warning: XQuartz not found. Install with 'brew install --cask xquartz'"; \
		sleep 1; \
		if command -v xhost >/dev/null 2>&1; then \
			DISPLAY=$${DISPLAY:-:0} xhost +localhost; \
		elif [ -x /opt/X11/bin/xhost ]; then \
			DISPLAY=$${DISPLAY:-:0} /opt/X11/bin/xhost +localhost; \
		else \
			echo "Warning: xhost not found. GUI might not appear. Install XQuartz: brew install --cask xquartz"; \
		fi; \
	fi

docker-run-client: docker-build-client x11-setup
	@echo "Starting client..."
	docker run --rm -it --name $(CLIENT_NAME) \
		-e DISPLAY=host.docker.internal:0 \
		-v /tmp/.X11-unix:/tmp/.X11-unix \
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

docker-prune: docker-down
	@echo "Pruning all stopped containers, dangling images, and unused networks..."
	docker container prune -f
	docker image prune -f
	docker network prune -f

logs:
	docker logs -f $(SERVER_NAME)

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
	@EXTRA_VARS="-e target_hosts=$(ANSIBLE_TARGET_HOSTS)"; \
	if [ -n "$(CLOUDFLARED_TUNNEL_TOKEN)" ]; then EXTRA_VARS="$$EXTRA_VARS -e tunnel_token=$(CLOUDFLARED_TUNNEL_TOKEN)"; fi; \
	if [ -n "$(REPO_URL)" ]; then EXTRA_VARS="$$EXTRA_VARS -e repo_url=$(REPO_URL)"; fi; \
	if [ -n "$(PROJECT_DIR)" ]; then EXTRA_VARS="$$EXTRA_VARS -e project_dir=$(PROJECT_DIR)"; fi; \
	ansible-playbook $(ANSIBLE_INVENTORY) ansible/playbook.yml $$EXTRA_VARS $(ANSIBLE_ARGS)

ansible-test:
	@if [ -z "$(COMPONENT)" ]; then \
		echo "Error: COMPONENT argument is required."; \
		echo "Usage: make ansible-test COMPONENT=<Led|Motor|Ultrasonic|Infrared|Servo|ADC|Buzzer|Camera|Battery|Motor-All|Non-Motor-All> [DURATION=60s]"; \
		exit 1; \
	fi
	@echo "🧪 Running hardware test via Ansible for $(COMPONENT)..."
	@EXTRA_VARS="-e component=$(COMPONENT) -e server_image=$(SERVER_IMAGE)"; \
	if [ -n "$(DURATION)" ]; then EXTRA_VARS="$$EXTRA_VARS -e test_duration=$(DURATION)"; fi; \
	if [ -n "$(RESTART)" ]; then EXTRA_VARS="$$EXTRA_VARS -e restart=$(RESTART)"; fi; \
	if [ -n "$(PROJECT_DIR)" ]; then EXTRA_VARS="$$EXTRA_VARS -e project_dir=$(PROJECT_DIR)"; fi; \
	ansible-playbook $(ANSIBLE_INVENTORY) ansible/test.yml $$EXTRA_VARS $(ANSIBLE_ARGS)

# ==============================================================================
# Local Development
# ==============================================================================

.PHONY: clean-install install rebuild-hardware venv venv-cleanup run-server run-client

clean-install:
	rm -rf node_modules package-lock.json
	npm install

install:
	@echo "Installing requirements into venv..."
	@. venv/bin/activate && pip install --upgrade pip
	@if grep -q "Raspberry Pi" /sys/firmware/devicetree/base/model 2>/dev/null; then \
		echo "Raspberry Pi detected. Installing requirements, excluding those provided by apt..."; \
		grep -v -e "PyQt5" -e "numpy" -e "gpiozero" src/requirements.txt > requirements.tmp; \
		. venv/bin/activate && pip install -r requirements.tmp; \
		rm requirements.tmp; \
	else \
		echo "Non-RPi OS detected. Installing requirements (excluding hardware libs)..."; \
		grep -v -e "rpi-ws281x" src/requirements.txt > requirements.tmp; \
		. venv/bin/activate && pip install -r requirements.tmp; \
		rm requirements.tmp; \
	fi

rebuild-hardware:
	@echo "Rebuilding hardware-specific libraries..."
	@. venv/bin/activate && pip install --force-reinstall --no-cache-dir rpi-ws281x || echo "Warning: rpi-ws281x failed to build. Using mocks."

venv:
	@if grep -q "Raspberry Pi" /sys/firmware/devicetree/base/model 2>/dev/null; then \
		echo "Raspberry Pi detected. Installing system dependencies..."; \
		sudo apt-get update && sudo apt-get install -y python3-dev python3-pyqt5 python3-numpy python3-gpiozero; \
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

run-client:
	. venv/bin/activate && python3 src/Client/Main.py

tunnel-control:
	@echo "Opening control tunnel to $(TUNNEL_HOSTNAME) on localhost:5000..."
	cloudflared access tcp --hostname $(TUNNEL_HOSTNAME) --url localhost:5000

tunnel-video:
	@echo "Opening video tunnel to $(TUNNEL_VIDEO_HOSTNAME) on localhost:8000..."
	cloudflared access tcp --hostname $(TUNNEL_VIDEO_HOSTNAME) --url localhost:8000

tunnels:
	@echo "Spawning tunnels in separate terminals..."
	@if [ "$$(uname)" = "Darwin" ]; then \
		osascript -e 'tell application "Terminal" to do script "cd \"$(CURDIR)\" && make tunnel-control"'; \
		osascript -e 'tell application "Terminal" to do script "cd \"$(CURDIR)\" && make tunnel-video"'; \
	else \
		echo "Auto-spawning terminals is only supported on macOS currently."; \
		echo "Please run 'make tunnel-control' and 'make tunnel-video' in separate terminals manually."; \
	fi