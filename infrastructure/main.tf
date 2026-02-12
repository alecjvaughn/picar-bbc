# 1. Build the Root Image (Level 1)
resource "docker_image" "root_base" {
  name = "local/root_base:latest"
  build {
    context    = ".." # Path to Root Dockerfile
    dockerfile = "/docker/images/root/Dockerfile"
  }
}

# 2. Build the Intermediate Image (Level 2)
resource "docker_image" "python_middleware" {
  name = "local/python_middleware:latest"
  build {
    context    = ".."
    dockerfile = "/docker/images/middleware/Dockerfile"
  }
  # Ensure Root is built first
  depends_on = [docker_image.root_base]
}

# 3. Build the Application Image (Level 3)
resource "docker_image" "my_app" {
  name = "local/my-app:latest"
  build {
    context    = ".."
    dockerfile = "/docker/images/app/Dockerfile"
  }
  # Ensure Middleware is built first
  depends_on = [docker_image.python_middleware]
}

# Define the network resource referenced by the container
resource "docker_network" "data_platform" {
  name = "data_platform_network"
}

# 4. Deploy the Container
resource "docker_container" "app_service" {
  name  = "production_service"
  image = docker_image.my_app.image_id

  # Network configuration for communicating with other services (e.g., Kafka/MinIO)
  networks_advanced {
    name = docker_network.data_platform.name
  }

  env = [
    "ENVIRONMENT=production",
    "GOOGLE_APPLICATION_CREDENTIALS=/tmp/keys/application_default_credentials.json",
    "GOOGLE_CLOUD_PROJECT=aleclabs-website"
  ]

  volumes {
    host_path      = pathexpand("~/.config/gcloud/application_default_credentials.json")
    container_path = "/tmp/keys/application_default_credentials.json"
    read_only      = true
  }

  ports {
    internal = 8080
    external = 8080
  }
}

# Output the correct URL for easy access
output "application_url" {
  value = "http://localhost:8080"
}
