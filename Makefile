# Use bash for shell commands
SHELL := /bin/bash

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
	@echo "  make logs                : View server logs"
	@echo ""
	@echo "Ansible Workflow:"
	@echo "  make ansible-ping        : Ping the Raspberry Pi via Ansible"
	@echo "  make ansible-deploy      : Run the Ansible playbook to configure/deploy"
	@echo ""
	@echo "Local Development:"
	@echo "  make venv                : Create/Update virtual environment"
	@echo "  make install             : Install dependencies to venv"
	@echo "  make run-server          : Run server locally"
	@echo "  make run-client          : Run client locally"
	@echo "  make clean-install       : Clean node_modules (if applicable) and reinstall"
	@echo "--------------------------------------------------------------------------------"

# ==============================================================================
# Terraform Workflow
# ==============================================================================

.PHONY: tf-init up down reload tf-clean

tf-init:
	cd $(TF_DIR) && terraform init

up: tf-init
	@if [ -z "$(CLOUDFLARED_TUNNEL_TOKEN)" ]; then \
		echo "⚠️  CLOUDFLARED_TUNNEL_TOKEN is not set. Cloudflare Tunnel will be SKIPPED (or destroyed if it exists)."; \
	else \
		echo "✅  CLOUDFLARED_TUNNEL_TOKEN found. Cloudflare Tunnel will be deployed."; \
	fi
	@echo "Ensuring manual container is removed to prevent port conflicts..."
	-docker rm -f $(SERVER_NAME) 2>/dev/null || true
	cd $(TF_DIR) && terraform apply -auto-approve -var="tunnel_token=$(CLOUDFLARED_TUNNEL_TOKEN)"

down:
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

.PHONY: docker-build docker-rebuild create-network docker-run-server debug-server x11-setup docker-run-client docker-run-tunnel docker-up docker-down docker-clean logs

docker-build:
	docker build $(BUILD_ARGS) -t $(ROOT_IMAGE) -f docker/images/root/Dockerfile .
	docker build $(BUILD_ARGS) -t $(MIDDLEWARE_IMAGE) -f docker/images/middleware/Dockerfile .
	docker build $(BUILD_ARGS) -t $(SERVER_IMAGE) -f docker/images/server/Dockerfile .
	docker build $(BUILD_ARGS) -t $(CLIENT_IMAGE) -f docker/images/client/Dockerfile .

docker-rebuild:
	$(MAKE) docker-build BUILD_ARGS="--no-cache"

create-network:
	docker network create $(NETWORK_NAME) 2>/dev/null || true

docker-run-server: docker-build create-network
	-docker rm -f $(SERVER_NAME) 2>/dev/null || true
	docker run --rm -d --name $(SERVER_NAME) \
		--network $(NETWORK_NAME) \
		$(PORTS) \
		$(SERVER_IMAGE)

debug-server: docker-build
	@echo "Cleaning up old debug container..."
	-docker rm -f $(DEBUG_SERVER_NAME) 2>/dev/null || true
	@echo "Starting server in debug mode (foreground)..."
	docker run --name $(DEBUG_SERVER_NAME) \
		$(PORTS) \
		$(SERVER_IMAGE)

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

docker-run-client: docker-build x11-setup
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
	docker run --rm -d --name $(TUNNEL_NAME) --restart unless-stopped \
		--network $(NETWORK_NAME) \
		-e TUNNEL_TOKEN=$(CLOUDFLARED_TUNNEL_TOKEN) \
		$(SERVER_IMAGE) cloudflared tunnel run

docker-up: docker-run-server

docker-down:
	docker stop $(SERVER_NAME) $(CLIENT_NAME) $(DEBUG_SERVER_NAME) $(TUNNEL_NAME) || true
	docker rm $(SERVER_NAME) $(CLIENT_NAME) $(DEBUG_SERVER_NAME) $(TUNNEL_NAME) || true

docker-clean: docker-down
	docker rmi $(SERVER_IMAGE) $(CLIENT_IMAGE) $(MIDDLEWARE_IMAGE) $(ROOT_IMAGE) || true

logs:
	docker logs -f $(SERVER_NAME)

# ==============================================================================
# Ansible Workflow
# ==============================================================================

.PHONY: ansible-ping ansible-deploy

ansible-ping:
	ansible -i ansible/inventory.ini picar -m ping

ansible-deploy:
	@if [ -n "$(CLOUDFLARED_TUNNEL_TOKEN)" ]; then \
		ansible-playbook -i ansible/inventory.ini ansible/playbook.yml -e "tunnel_token=$(CLOUDFLARED_TUNNEL_TOKEN)"; \
	else \
		ansible-playbook -i ansible/inventory.ini ansible/playbook.yml; \
	fi

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
		echo "Non-RPi OS detected. Installing all requirements..."; \
		. venv/bin/activate && pip install -r src/requirements.txt; \
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