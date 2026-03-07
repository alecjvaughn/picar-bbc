# Variables
TF_DIR := infrastructure
SERVER_NAME := picar-server
CLIENT_NAME := picar-client
DEBUG_SERVER_NAME := picar-server-debug
SERVER_IMAGE := local/picar-server:latest
CLIENT_IMAGE := local/picar-client:latest
MIDDLEWARE_IMAGE := local/python_middleware:latest
ROOT_IMAGE := local/root_base:latest
PORTS := -p 5000:5000 -p 8000:8000

.PHONY: help up down reload logs tf-init docker-up docker-down docker-clean clean-install docker-rebuild venv venv-cleanup tf-clean run-server run-client install rebuild-hardware debug-server x11-setup docker-build

help:
	@echo "Usage:"
	@echo "  make up          : Start the application using Terraform (Preferred)"
	@echo "  make down        : Destroy infrastructure and clean up images"
	@echo "  make reload      : Rebuild the app image and restart (Terraform)"
	@echo "  make tf-clean    : Remove Terraform state and lock files"
	@echo "  make logs        : View container logs"
	@echo "  make docker-up   : Build and run using Docker commands (Alternative)"
	@echo "  make docker-down : Stop and remove Docker container"
	@echo "  make docker-run-server : Run the server container"
	@echo "  make debug-server      : Run the server container in debug mode (foreground)"
	@echo "  make docker-run-client : Run the client container"
	@echo "  make clean-install : Clean node_modules and reinstall dependencies"
	@echo "  make venv        : Create a local Python virtual environment for testing"
	@echo "  make venv-cleanup  : Remove the local Python virtual environment"
	@echo "  make install     : Install dependencies into existing venv"
	@echo "  make rebuild-hardware : Attempt to rebuild/reinstall hardware libraries"
	@echo "  make run-server  : Run the server locally (headless)"
	@echo "  make run-client  : Run the client locally"

# --- Terraform Workflow (Preferred) ---

tf-init:
	cd $(TF_DIR) && terraform init

up: tf-init
	cd $(TF_DIR) && terraform apply -auto-approve

# Thorough cleanup: Destroy resources and ensure images are removed
down:
	cd $(TF_DIR) && terraform destroy -auto-approve
	@echo "Cleaning up any dangling images..."
	-docker rmi $(SERVER_IMAGE) $(CLIENT_IMAGE) $(MIDDLEWARE_IMAGE) $(ROOT_IMAGE) 2>/dev/null || true
	-docker network rm data_platform_network 2>/dev/null || true

# Remove Terraform state, locks, and cached plugins for a fresh start
tf-clean:
	rm -rf $(TF_DIR)/.terraform $(TF_DIR)/.terraform.lock.hcl $(TF_DIR)/terraform.tfstate $(TF_DIR)/terraform.tfstate.backup

# Clean node_modules and reinstall dependencies locally
clean-install:
	rm -rf node_modules package-lock.json
	npm install

# Force rebuild of the application image without destroying network/base images
reload:
	cd $(TF_DIR) && terraform taint docker_image.picar_server
	cd $(TF_DIR) && terraform apply -auto-approve

logs:
	docker logs -f $(SERVER_NAME)

# --- Docker Manual Workflow (Alternative) ---

BUILD_ARGS ?=

docker-build:
	docker build $(BUILD_ARGS) -t $(ROOT_IMAGE) -f docker/images/root/Dockerfile .
	docker build $(BUILD_ARGS) -t $(MIDDLEWARE_IMAGE) -f docker/images/middleware/Dockerfile .
	docker build $(BUILD_ARGS) -t $(SERVER_IMAGE) -f docker/images/server/Dockerfile .
	docker build $(BUILD_ARGS) -t $(CLIENT_IMAGE) -f docker/images/client/Dockerfile .

docker-rebuild:
	$(MAKE) docker-build BUILD_ARGS="--no-cache"

docker-run-server: docker-build
	docker run --rm -d --name $(SERVER_NAME) \
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

docker-up: docker-run-server

docker-down:
	docker stop $(SERVER_NAME) $(CLIENT_NAME) $(DEBUG_SERVER_NAME) || true
	docker rm $(SERVER_NAME) $(CLIENT_NAME) $(DEBUG_SERVER_NAME) || true

docker-clean: docker-down
	docker rmi $(SERVER_IMAGE) $(CLIENT_IMAGE) $(MIDDLEWARE_IMAGE) $(ROOT_IMAGE) || true

install:
	@echo "Installing requirements..."
	. venv/bin/activate && pip install --upgrade pip && pip install -r src/requirements.txt
	@echo "Attempting to install hardware-specific libraries..."
	@. venv/bin/activate && pip install rpi-ws281x || echo "Warning: rpi-ws281x failed to install. This is expected on non-RPi hardware. The application will use mocks."

rebuild-hardware:
	@echo "Rebuilding hardware-specific libraries..."
	@. venv/bin/activate && pip install --force-reinstall --no-cache-dir rpi-ws281x || echo "Warning: rpi-ws281x failed to build. Using mocks."

venv:
	test -d venv || python3 -m venv venv
	@$(MAKE) install
	@echo "Virtual environment ready. Activate with: source venv/bin/activate"

venv-cleanup:
	rm -rf venv
	@echo "Virtual environment removed."

run-server:
	. venv/bin/activate && python3 src/Server/main.py --no-gui

run-client:
	. venv/bin/activate && python3 src/Client/Main.py