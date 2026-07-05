# Install Docker & Docker Compose
sudo apt update
sudo apt install -y docker.io docker-compose-v2 git

sudo docker --version
sudo docker compose version

sudo usermod -aG docker $USER

sudo newgrp docker

#git clone
git clone https://github.com/Ahmed-Reda-Ragab/devops-mosalam-lab-2.git

# Navigate to the project directory
cd devops-mosalam-lab-2

# Start the services using Docker Compose
docker compose up -d

docker ps