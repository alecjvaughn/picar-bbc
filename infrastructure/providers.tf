terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker" # The standard provider for local Docker
      version = "~> 3.6.2"
    }
  }
}

provider "docker" {
  # host = "unix:///var/run/docker.sock" # Leave commented to auto-detect (works on Pi and Mac if DOCKER_HOST is set)
}
