terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker" # The standard provider for local Docker
      version = "~> 3.6.2"
    }
  }
}

provider "docker" {
  host = "unix:///Users/alecjvaughn/.colima/default/docker.sock" # Adjust for Windows if necessary
}
