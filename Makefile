# Variables
TF_DIR := infrastructure
APP_NAME := production_service
APP_IMAGE := local/my-app:latest
MIDDLEWARE_IMAGE := local/python_middleware:latest
ROOT_IMAGE := local/root_base:latest
PORT := 8080

.PHONY: help up down reload logs tf-init docker-up docker-down docker-clean clean-install docker-rebuild

help:
	@echo "Usage:"
	@echo "  make up          : Start the application using Terraform (Preferred)"
	@echo "  make down        : Destroy infrastructure and clean up images"
	@echo "  make reload      : Rebuild the app image and restart (Terraform)"
	@echo "  make tf-clean    : Remove Terraform state and lock files"
	@echo "  make logs        : View container logs"
	@echo "  make docker-up   : Build and run using Docker commands (Alternative)"
	@echo "  make docker-down : Stop and remove Docker container"
	@echo "  make docker-rebuild : Force rebuild of Docker images (no cache)"
	@echo "  make clean-install : Clean node_modules and reinstall dependencies"

# --- Terraform Workflow (Preferred) ---

tf-init:
	cd $(TF_DIR) && terraform init

up: tf-init
	cd $(TF_DIR) && terraform apply -auto-approve

# Thorough cleanup: Destroy resources and ensure images are removed
down:
	cd $(TF_DIR) && terraform destroy -auto-approve
	@echo "Cleaning up any dangling images..."
	-docker rmi $(APP_IMAGE) $(MIDDLEWARE_IMAGE) $(ROOT_IMAGE) 2>/dev/null || true
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
	cd $(TF_DIR) && terraform taint docker_image.my_app
	cd $(TF_DIR) && terraform apply -auto-approve

logs:
	docker logs -f $(APP_NAME)

# --- Docker Manual Workflow (Alternative) ---

docker-build:
	docker build -t $(ROOT_IMAGE) -f docker/images/root/Dockerfile .
	docker build -t $(MIDDLEWARE_IMAGE) -f docker/images/middleware/Dockerfile .
	docker build -t $(APP_IMAGE) -f docker/images/app/Dockerfile .

docker-rebuild:
	docker build --no-cache -t $(ROOT_IMAGE) -f docker/images/root/Dockerfile .
	docker build --no-cache -t $(MIDDLEWARE_IMAGE) -f docker/images/middleware/Dockerfile .
	docker build --no-cache -t $(APP_IMAGE) -f docker/images/app/Dockerfile .

docker-run: docker-build
	docker run --rm -d --name $(APP_NAME) \
		-p $(PORT):$(PORT) \
		-e ENVIRONMENT=production \
		-e GOOGLE_APPLICATION_CREDENTIALS=/tmp/keys/application_default_credentials.json \
		-e GOOGLE_CLOUD_PROJECT=aleclabs-website \
		-v $(HOME)/.config/gcloud/application_default_credentials.json:/tmp/keys/application_default_credentials.json:ro \
		$(APP_IMAGE)

docker-up: docker-run

docker-down:
	docker stop $(APP_NAME) || true
	docker rm $(APP_NAME) || true

docker-clean: docker-down
	docker rmi $(APP_IMAGE) $(MIDDLEWARE_IMAGE) $(ROOT_IMAGE) || true