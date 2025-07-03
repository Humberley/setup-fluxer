#!/bin/bash

# Cores e estilos
VERDE='\033[1;32m'
AZUL='\033[1;34m'
AMARELO='\033[1;33m'
VERMELHO='\033[1;31m'
NEGRITO='\033[1m'
RESET='\033[0m'

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

# Explicação sobre o wildcard
echo -e "${AZUL}${NEGRITO}🌐 ANTES DE CONTINUAR:${RESET}"
echo -e "${AMARELO}Configure um registro DNS WILDCARD na sua Cloudflare assim:${RESET}"
echo -e "${NEGRITO}Tipo:    A${RESET}"
echo -e "${NEGRITO}Nome:    *${RESET}"
echo -e "${NEGRITO}IP:      (mesmo IP desta VPS)${RESET}"
echo -e "${NEGRITO}Proxy:   DNS only (⚠️ desativado)${RESET}"
echo
echo -e "${AZUL}Isso permitirá que os seguintes subdomínios funcionem automaticamente:${RESET}"
echo -e "  • portainer"
echo -e "  • n8n, nwn (webhook)"
echo -e "  • tpb, tpv (typebot)"
echo -e "  • minio, s3"
echo -e "  • evo (evolution api)"
echo

# Solicita domínio raiz
read -p "🌐 Qual é o domínio principal (ex: fluxer.com.br): " DOMINIO_RAIZ

# Gera subdomínios automaticamente
PORTAINER_DOMAIN="portainer.${DOMINIO_RAIZ}"
N8N_EDITOR_DOMAIN="n8n.${DOMINIO_RAIZ}"
N8N_WEBHOOK_DOMAIN="nwn.${DOMINIO_RAIZ}"
TYPEBOT_EDITOR_DOMAIN="tpb.${DOMINIO_RAIZ}"
TYPEBOT_VIEWER_DOMAIN="tpv.${DOMINIO_RAIZ}"
MINIO_CONSOLE_DOMAIN="minio.${DOMINIO_RAIZ}"
MINIO_S3_DOMAIN="s3.${DOMINIO_RAIZ}"
EVOLUTION_DOMAIN="evo.${DOMINIO_RAIZ}"

# Solicita senha do Portainer
read -s -p "🔑 Senha do Portainer: " PORTAINER_PASSWORD
echo

# Solicita usuário e senha do MinIO
read -p "👤 Usuário root do MinIO: " MINIO_ROOT_USER
read -s -p "🔑 Senha root do MinIO: " MINIO_ROOT_PASSWORD
echo

# Gera chaves automaticamente
POSTGRES_PASSWORD=$(openssl rand -hex 16)
N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
TYPEBOT_ENCRYPTION_KEY=$(openssl rand -hex 16)
EVOLUTION_API_KEY=$(openssl rand -hex 16)

# Criação do .env
echo -e "\n📄 Gerando arquivo .env..."
cat > .env <<EOF
# Rede e certificados
REDE_DOCKER=fluxerNet
LE_EMAIL=fluxerautoma@gmail.com

# Portainer
PORTAINER_DOMAIN=${PORTAINER_DOMAIN}
PORTAINER_PASSWORD=${PORTAINER_PASSWORD}
PORTAINER_VOLUME=portainer_data

# PostgreSQL
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_VOLUME=postgres_data

# Redis
REDIS_VOLUME=redis_data
REDIS_URI=redis://redis:6379/8

# MinIO
MINIO_CONSOLE_DOMAIN=${MINIO_CONSOLE_DOMAIN}
MINIO_S3_DOMAIN=${MINIO_S3_DOMAIN}
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
MINIO_VOLUME=minio_data
S3_ENABLED=false
S3_ACCESS_KEY=
S3_SECRET_KEY=
S3_ENDPOINT=${MINIO_S3_DOMAIN}

# n8n
N8N_EDITOR_DOMAIN=${N8N_EDITOR_DOMAIN}
N8N_WEBHOOK_DOMAIN=${N8N_WEBHOOK_DOMAIN}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_SMTP_USER=fluxerautoma@gmail.com
N8N_SMTP_PASS=teste

# Typebot
TYPEBOT_EDITOR_DOMAIN=${TYPEBOT_EDITOR_DOMAIN}
TYPEBOT_VIEWER_DOMAIN=${TYPEBOT_VIEWER_DOMAIN}
TYPEBOT_ENCRYPTION_KEY=${TYPEBOT_ENCRYPTION_KEY}

# Evolution
EVOLUTION_DOMAIN=${EVOLUTION_DOMAIN}
EVOLUTION_API_KEY=${EVOLUTION_API_KEY}
EVOLUTION_VOLUME=evolution_instances
EOF

echo -e "${VERDE}✔ .env criado com sucesso!${RESET}"

# Mostrar credenciais e URLs
echo -e "\n${AZUL}${NEGRITO}🔑 RESUMO FINAL:${RESET}"
echo -e "${VERDE}Painel Portainer:     https://${PORTAINER_DOMAIN}${RESET}"
echo -e "${VERDE}Painel n8n (editor):  https://${N8N_EDITOR_DOMAIN}${RESET}"
echo -e "${VERDE}Webhook n8n:          https://${N8N_WEBHOOK_DOMAIN}${RESET}"
echo -e "${VERDE}Builder Typebot:      https://${TYPEBOT_EDITOR_DOMAIN}${RESET}"
echo -e "${VERDE}Viewer Typebot:       https://${TYPEBOT_VIEWER_DOMAIN}${RESET}"
echo -e "${VERDE}MinIO Painel:         https://${MINIO_CONSOLE_DOMAIN}${RESET}"
echo -e "${VERDE}MinIO S3:             https://${MINIO_S3_DOMAIN}${RESET}"
echo -e "${VERDE}Evolution API:        https://${EVOLUTION_DOMAIN}${RESET}"
echo
echo -e "${NEGRITO}🔐 Senha do Portainer:       ${PORTAINER_PASSWORD}${RESET}"
echo -e "${NEGRITO}🔐 Usuário root do MinIO:    ${MINIO_ROOT_USER}${RESET}"
echo -e "${NEGRITO}🔐 Senha root do MinIO:      ${MINIO_ROOT_PASSWORD}${RESET}"
echo -e "${NEGRITO}🔐 Chave da Evolution API:   ${EVOLUTION_API_KEY}${RESET}"
