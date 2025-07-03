#!/bin/bash

# Estilo
VERDE='\033[1;32m'
AZUL='\033[1;34m'
AMARELO='\033[1;33m'
VERMELHO='\033[1;31m'
RESET='\033[0m'

echo -e "${AZUL}🚀 Iniciando instalador Fluxer...${RESET}"

# 1. Verifica se Docker está instalado
if ! command -v docker &> /dev/null; then
  echo -e "${AMARELO}⚙️ Docker não encontrado. Instalando...${RESET}"
  curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh
  echo -e "${VERDE}✅ Docker instalado com sucesso.${RESET}"
else
  echo -e "${VERDE}✅ Docker já está instalado.${RESET}"
fi

# 2. Verifica se o Swarm está iniciado
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
  echo -e "${AZUL}🌀 Iniciando Docker Swarm...${RESET}"
  docker swarm init
else
  echo -e "${VERDE}✅ Docker Swarm já está ativo.${RESET}"
fi

# 3. Clona o repositório para /opt/setup-fluxer
INSTALL_DIR="/opt/setup-fluxer"

echo -e "${AZUL}📥 Clonando repositório para ${INSTALL_DIR}...${RESET}"

if [ -d "$INSTALL_DIR" ]; then
  echo -e "${AMARELO}⚠️ Diretório ${INSTALL_DIR} já existe. Atualizando...${RESET}"
  cd "$INSTALL_DIR"
  git pull
else
  git clone https://github.com/Humberley/setup-fluxer.git "$INSTALL_DIR"
  cd "$INSTALL_DIR" || { echo -e "${VERMELHO}Erro ao acessar o diretório clonado${RESET}"; exit 1; }
fi

# 4. Torna o instalador real executável
chmod +x fluxer-install.sh

# 5. Executa o instalador real
echo -e "${AZUL}🚀 Executando instalador completo...${RESET}"
./fluxer-install.sh
