#!/bin/bash

# Cores
VERDE='\033[1;32m'
AZUL='\033[1;34m'
AMARELO='\033[1;33m'
VERMELHO='\033[1;31m'
NEGRITO='\033[1m'
RESET='\033[0m'

# Função para gerar strings seguras
generate_secret() {
  openssl rand -hex 16
}

clear
echo -e "${AZUL}${NEGRITO}"
echo "███████╗██╗     ██╗   ██ ██╗  ██╗███████╗██████╗     ███████╗███████╗████████╗██╗   ██╗██████╗ "
echo "██╔════╝██║     ██║   ██ ║██║ ██╔╝██╔════╝██╔══██╗    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗"
echo "█████╗  ██║     ██║   ██ ║█████╔╝ █████╗  ██████╔╝    ███████╗█████╗     ██║   ██║   ██║██████╔╝"
echo "██╔══╝  ██║     ██║   ██ ║██╔═██╗ ██╔══╝  ██╔══╝██     ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ "
echo "██     ╗███████╗╚██████╔ ╝██║  ██╗███████╗██║     ██    ███████║███████╗   ██║   ╚██████╔╝██║     "
echo "╚══════╝╚══════╝ ╚═════╝  ╚═╝  ╚═╝╚══════╝╚═╝         ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     "
echo -e "${RESET}"
echo -e "${VERDE}${NEGRITO}🛠 INSTALADOR FLUXER - CONFIGURAÇÃO COMPLETA DA VPS${RESET}"
echo

# Coleta de variáveis essenciais
echo -e "${AZUL}${NEGRITO}🌐 CONFIGURAÇÃO INICIAL:${RESET}"
read -p "➤ Nome da rede Docker Swarm: " REDE_DOCKER
read -p "➤ E-mail para certificados SSL: " LE_EMAIL

# Domínios
echo -e "\n${AZUL}${NEGRITO}🌐 DOMÍNIOS DOS SERVIÇOS:${RESET}"
read -p "➤ Domínio do Portainer: " PORTAINER_DOMAIN
read -p "➤ Domínio do N8N (editor): " N8N_EDITOR_DOMAIN
read -p "➤ Domínio do N8N (webhook): " N8N_WEBHOOK_DOMAIN
read -p "➤ Domínio do Typebot (editor): " TYPEBOT_EDITOR_DOMAIN
read -p "➤ Domínio do Typebot (viewer): " TYPEBOT_VIEWER_DOMAIN
read -p "➤ Domínio do MinIO (painel): " MINIO_CONSOLE_DOMAIN
read -p "➤ Domínio do MinIO (S3): " MINIO_S3_DOMAIN
read -p "➤ Domínio da Evolution API: " EVOLUTION_DOMAIN

# Senhas e dados sensíveis
echo -e "\n${AZUL}${NEGRITO}🔐 CREDENCIAIS:${RESET}"
read -s -p "➤ Senha do Portainer: " PORTAINER_PASSWORD && echo
read -p "➤ Usuário root do MinIO: " MINIO_ROOT_USER
read -s -p "➤ Senha root do MinIO (mín. 8 caracteres): " MINIO_ROOT_PASSWORD && echo
read -p "➤ E-mail SMTP (usado pelo n8n e Typebot): " N8N_SMTP_USER
read -s -p "➤ Senha SMTP (app password): " N8N_SMTP_PASS && echo

# Variáveis geradas automaticamente
POSTGRES_PASSWORD=$(generate_secret)
N8N_ENCRYPTION_KEY=$(generate_secret)
TYPEBOT_ENCRYPTION_KEY=$(generate_secret)
EVOLUTION_API_KEY=$(generate_secret)

# Volumes fixos
PORTAINER_VOLUME="portainer_data"
POSTGRES_VOLUME="postgres_data"
REDIS_VOLUME="redis_data"
MINIO_VOLUME="minio_data"
EVOLUTION_VOLUME="evolution_instances"
S3_ENABLED="false"
S3_ACCESS_KEY=""
S3_SECRET_KEY=""
S3_ENDPOINT=$MINIO_S3_DOMAIN
REDIS_URI="redis://redis:6379/8"

# Criar arquivo .env
echo -e "\n${AZUL}${NEGRITO}📄 Gerando arquivo .env...${RESET}"

cat > .env <<EOF
# Rede e certificados
REDE_DOCKER=$REDE_DOCKER
LE_EMAIL=$LE_EMAIL

# Portainer
PORTAINER_DOMAIN=$PORTAINER_DOMAIN
PORTAINER_PASSWORD=$PORTAINER_PASSWORD
PORTAINER_VOLUME=$PORTAINER_VOLUME

# PostgreSQL
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_VOLUME=$POSTGRES_VOLUME

# Redis
REDIS_VOLUME=$REDIS_VOLUME
REDIS_URI=$REDIS_URI

# MinIO
MINIO_CONSOLE_DOMAIN=$MINIO_CONSOLE_DOMAIN
MINIO_S3_DOMAIN=$MINIO_S3_DOMAIN
MINIO_ROOT_USER=$MINIO_ROOT_USER
MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD
MINIO_VOLUME=$MINIO_VOLUME
S3_ENABLED=$S3_ENABLED
S3_ACCESS_KEY=$S3_ACCESS_KEY
S3_SECRET_KEY=$S3_SECRET_KEY
S3_ENDPOINT=$S3_ENDPOINT

# n8n
N8N_EDITOR_DOMAIN=$N8N_EDITOR_DOMAIN
N8N_WEBHOOK_DOMAIN=$N8N_WEBHOOK_DOMAIN
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
N8N_SMTP_USER=$N8N_SMTP_USER
N8N_SMTP_PASS=$N8N_SMTP_PASS

# Typebot
TYPEBOT_EDITOR_DOMAIN=$TYPEBOT_EDITOR_DOMAIN
TYPEBOT_VIEWER_DOMAIN=$TYPEBOT_VIEWER_DOMAIN
TYPEBOT_ENCRYPTION_KEY=$TYPEBOT_ENCRYPTION_KEY

# Evolution
EVOLUTION_DOMAIN=$EVOLUTION_DOMAIN
EVOLUTION_API_KEY=$EVOLUTION_API_KEY
EVOLUTION_VOLUME=$EVOLUTION_VOLUME
EOF

echo -e "${VERDE}✔ .env criado com sucesso!${RESET}"

# Deploy dos serviços na ordem correta
echo -e "\n${AZUL}${NEGRITO}🚀 Realizando deploy dos serviços...${RESET}"

SERVICOS=(traefik redis postgres portainer minio n8n typebot evolution)
for servico in "${SERVICOS[@]}"; do
  echo -e "${AMARELO}🔧 Deploy do serviço: $servico${RESET}"
  envsubst < stacks/$servico/${servico}.template.yml | docker stack deploy -c - $servico
done

echo -e "\n${VERDE}${NEGRITO}✅ Instalação finalizada com sucesso!${RESET}"
