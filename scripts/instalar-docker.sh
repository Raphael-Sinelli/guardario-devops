#!/usr/bin/env bash
# =====================================================================================
# GuardaRio · instala o Docker Engine e o plugin do Docker Compose na VM (Ubuntu).
# Segue o passo a passo oficial: https://docs.docker.com/engine/install/ubuntu/
#
# Onde rodar: DENTRO da VM, depois do ssh.
# Uso:        ./scripts/instalar-docker.sh
# =====================================================================================
set -euo pipefail

if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
  echo "Docker e Docker Compose já estão instalados:"
  docker --version
  docker compose version
  exit 0
fi

echo "==> 1/4 Pacotes de apoio e chave do repositório oficial do Docker"
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl openssl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "==> 2/4 Repositório do Docker no apt"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update -y

echo "==> 3/4 Docker Engine, Buildx e Docker Compose"
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker

echo "==> 4/4 Usuário ${USER} no grupo docker (para rodar sem sudo)"
sudo usermod -aG docker "$USER"

echo
sudo docker --version
sudo docker compose version
echo
echo "Instalado. O grupo novo só vale num login novo. Rode agora:"
echo "  newgrp docker        (ou saia com 'exit' e entre de novo por ssh)"
echo "Depois:"
echo "  ./scripts/gerar-env.sh && docker compose up -d --build"
