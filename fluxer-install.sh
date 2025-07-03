#!/bin/bash

#-------------------------------------------------------------------------------
# Script: Instalador de Ambiente Fluxer
# Descrição: Coleta as informações do usuário, gera o .env e inicia cada
#            serviço como uma stack individual no Docker Swarm.
# Autor: Humberley / [Seu Nome]
# Versão: 2.4 (Corrige erro de chave YAML)
#-------------------------------------------------------------------------------

# === VARIÁVEIS DE CORES E ESTILOS ===
VERDE='\033[1;32m'
AZUL='\033[1;34m'
AMARELO='\033[1;33m'
VERMELHO='\033[1;31m'
NEGRITO='\033[1m'
RESET='\033[0m'

# === FUNÇÕES AUXILIARES ===
msg_header() {
    echo -e "\n${AZUL}${NEGRITO}# $1${RESET}"
}
msg_success() {
    echo -e "${VERDE}✔ $1${RESET}"
}
msg_warning() {
    echo -e "${AMARELO}⚠️ $1${RESET}"
}
msg_error() {
    echo -e "${VERMELHO}❌ ERRO: $1${RESET}"
    exit 1
}

# === FUNÇÃO PRINCIPAL ===
main() {
    clear
    # --- BANNER ---
    echo -e "${AZUL}${NEGRITO}"
    echo "███████╗██╗     ██╗   ██╗██╗  ██╗███████╗██████╗      ███████╗███████╗████████╗██╗  ██╗██████╗ "
    echo "██╔════╝██║     ██║   ██║██║ ██╔╝██╔════╝██╔══██╗     ██╔════╝██╔════╝╚══██╔══╝██║  ██║██╔══██╗"
    echo "█████╗  ██║     ██║   ██║█████╔╝ █████╗  ██████╔╝     ███████╗█████╗     ██║   ██║  ██║██████╔╝"
    echo "██╔══╝  ██║     ██║   ██║██╔═██╗ ██╔══╝  ██╔══╝██     ╚════██║██╔══╝     ██║   ██║  ██║██╔═══╝ "
    echo "██║     ███████╗ ╚██████╔╝██║  ██╗███████╗██║   ██     ███████║███████╗   ██║   ╚██████╔╝██║     "
    echo "╚═╝     ╚══════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝    ██     ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     "
    echo -e "${RESET}"
    echo -e "${VERDE}${NEGRITO}🛠 INSTALADOR FLUXER - CONFIGURAÇÃO COMPLETA DA VPS${RESET}"

    # --- VERIFICAÇÃO DO DOCKER SWARM ---
    msg_header "VERIFICANDO AMBIENTE DOCKER SWARM"
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        msg_warning "Docker Swarm não está ativo. A inicializar..."
        if ! docker swarm init; then
            msg_error "Falha ao inicializar o Docker Swarm."
        fi
    fi
    msg_success "Docker Swarm está ativo."

    # --- INSTRUÇÕES DNS ---
    msg_header "CONFIGURAÇÃO DNS (WILDCARD)"
    msg_warning "Antes de continuar, configure um registo DNS WILDCARD na sua Cloudflare:"
    echo -e "${NEGRITO}  Tipo:   A"
    echo -e "  Nome:   *"
    echo -e "  IP:     (O IP desta VPS)"
    echo -e "  Proxy:  DNS only (nuvem cinza, desativado)${RESET}"
    echo
    read -p "Pressione [Enter] para continuar após configurar o DNS..." < /dev/tty

    # --- COLETA DE DADOS DO USUÁRIO ---
    msg_header "COLETANDO INFORMAÇÕES"

    while [[ -z "$DOMINIO_RAIZ" ]]; do
        read -p "🌐 Qual é o seu domínio principal (ex: seudominio.com.br): " DOMINIO_RAIZ < /dev/tty
    done

    while [[ -z "$LE_EMAIL" ]]; do
        read -p "📧 Email para o certificado SSL (Let's Encrypt): " LE_EMAIL < /dev/tty
    done

    while true; do
        read -s -p "🔑 Digite uma senha para o Portainer: " PORTAINER_PASSWORD < /dev/tty; echo
        read -s -p "🔑 Confirme a senha do Portainer: " PORTAINER_PASSWORD_CONFIRM < /dev/tty; echo
        if [[ "$PORTAINER_PASSWORD" == "$PORTAINER_PASSWORD_CONFIRM" ]] && [[ -n "$PORTAINER_PASSWORD" ]]; then
            break
        else
            msg_warning "As senhas não coincidem ou estão vazias. Tente novamente."
        fi
    done

    while [[ -z "$MINIO_ROOT_USER" ]]; do
        read -p "👤 Utilizador root para o MinIO: " MINIO_ROOT_USER < /dev/tty
    done
    while true; do
        read -s -p "🔑 Digite uma senha para o MinIO: " MINIO_ROOT_PASSWORD < /dev/tty; echo
        read -s -p "🔑 Confirme a senha do MinIO: " MINIO_ROOT_PASSWORD_CONFIRM < /dev/tty; echo
        if [[ "$MINIO_ROOT_PASSWORD" == "$MINIO_ROOT_PASSWORD_CONFIRM" ]] && [[ -n "$MINIO_ROOT_PASSWORD" ]]; then
            break
        else
            msg_warning "As senhas não coincidem ou estão vazias. Tente novamente."
        fi
    done

    # --- GERAÇÃO DE VARIÁVEIS E SUBDOMÍNIOS ---
    msg_header "GERANDO CONFIGURAÇÕES"
    echo "Gerando subdomínios e chaves de segurança..."

    export DOMINIO_RAIZ LE_EMAIL PORTAINER_PASSWORD MINIO_ROOT_USER MINIO_ROOT_PASSWORD

    export PORTAINER_DOMAIN="portainer.${DOMINIO_RAIZ}"
    export N8N_EDITOR_DOMAIN="n8n.${DOMINIO_RAIZ}"
    export N8N_WEBHOOK_DOMAIN="nwn.${DOMINIO_RAIZ}"
    export TYPEBOT_EDITOR_DOMAIN="tpb.${DOMINIO_RAIZ}"
    export TYPEBOT_VIEWER_DOMAIN="tpv.${DOMINIO_RAIZ}"
    export MINIO_CONSOLE_DOMAIN="minio.${DOMINIO_RAIZ}"
    export MINIO_S3_DOMAIN="s3.${DOMINIO_RAIZ}"
    export EVOLUTION_DOMAIN="evo.${DOMINIO_RAIZ}"

    export POSTGRES_PASSWORD=$(openssl rand -hex 16)
    export N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
    export TYPEBOT_ENCRYPTION_KEY=$(openssl rand -hex 16)
    export EVOLUTION_API_KEY=$(openssl rand -hex 16)
    
    export PORTAINER_VOLUME="portainer_data"
    export POSTGRES_VOLUME="postgres_data"
    export REDIS_VOLUME="redis_data"
    export MINIO_VOLUME="minio_data"
    export EVOLUTION_VOLUME="evolution_instances"
    export REDE_DOCKER="fluxerNet"
    
    msg_success "Configurações geradas e exportadas para o ambiente."

    # --- CRIAÇÃO DO FICHEIRO .ENV ---
    echo "Criando o ficheiro de configuração .env..."
    cat > .env <<EOF
# Gerado por Fluxer Installer v2.4 em $(date)

# --- GERAL ---
REDE_DOCKER=fluxerNet
LE_EMAIL=${LE_EMAIL}

# --- PORTAINER ---
PORTAINER_DOMAIN=${PORTAINER_DOMAIN}
PORTAINER_PASSWORD=${PORTAINER_PASSWORD}

# --- BANCO DE DADOS (PostgreSQL) ---
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# --- ARMAZENAMENTO (MinIO) ---
MINIO_CONSOLE_DOMAIN=${MINIO_CONSOLE_DOMAIN}
MINIO_S3_DOMAIN=${MINIO_S3_DOMAIN}
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}

# --- N8N ---
N8N_EDITOR_DOMAIN=${N8N_EDITOR_DOMAIN}
N8N_WEBHOOK_DOMAIN=${N8N_WEBHOOK_DOMAIN}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}

# --- TYPEBOT ---
TYPEBOT_EDITOR_DOMAIN=${TYPEBOT_EDITOR_DOMAIN}
TYPEBOT_VIEWER_DOMAIN=${TYPEBOT_VIEWER_DOMAIN}
TYPEBOT_ENCRYPTION_KEY=${TYPEBOT_ENCRYPTION_KEY}

# --- EVOLUTION API ---
EVOLUTION_DOMAIN=${EVOLUTION_DOMAIN}
EVOLUTION_API_KEY=${EVOLUTION_API_KEY}
EOF
    msg_success "Ficheiro .env criado com sucesso!"

    # --- CHAMADA DA NOVA FUNÇÃO ---
    build_compose_file

    # --- INICIANDO OS SERVIÇOS ---
    msg_header "INICIANDO OS SERVIÇOS"
    
    echo "Criando a rede Docker (se não existir)..."
    docker network create fluxerNet >/dev/null 2>&1
    
    echo "Iniciando os contentores com 'docker-compose up -d'..."
    msg_warning "Este processo pode levar vários minutos. Por favor, aguarde."
    if docker-compose up -d; then
        msg_success "Todos os serviços foram iniciados com sucesso!"
    else
        msg_error "Houve um problema ao iniciar os serviços com o Docker Compose."
    fi

    # --- RESUMO FINAL ---
    msg_header "🎉 INSTALAÇÃO CONCLUÍDA 🎉"
    echo "Aguarde alguns minutos para que todos os serviços sejam iniciados."
    echo "Pode verificar o estado com o comando: ${NEGRITO}docker service ls${RESET}"
    echo "Abaixo estão os seus links de acesso:"
    echo
    echo -e "${NEGRITO}Painel Portainer:   https://${PORTAINER_DOMAIN}${RESET}"
    echo -e "${NEGRITO}Painel n8n (editor):  https://${N8N_EDITOR_DOMAIN}${RESET}"
    echo -e "${NEGRITO}Builder Typebot:      https://${TYPEBOT_EDITOR_DOMAIN}${RESET}"
    echo -e "${NEGRITO}MinIO Painel:         https://${MINIO_CONSOLE_DOMAIN}${RESET}"
    echo -e "${NEGRITO}Evolution API:        https://${EVOLUTION_DOMAIN}${RESET}"
    echo

    read -p "Deseja exibir as senhas e chaves geradas? (s/N): " SHOW_CREDS < /dev/tty
    if [[ "$SHOW_CREDS" =~ ^[Ss]$ ]]; then
        echo
        msg_header "CREDENCIAS GERADAS (guarde em local seguro)"
        echo -e "${NEGRITO}Senha do Portainer:      ${PORTAINER_PASSWORD}${RESET}"
        echo -e "${NEGRITO}Utilizador root do MinIO:   ${MINIO_ROOT_USER}${RESET}"
        echo -e "${NEGRITO}Senha root do MinIO:     ${MINIO_ROOT_PASSWORD}${RESET}"
        echo -e "${NEGRITO}Chave da Evolution API:  ${EVOLUTION_API_KEY}${RESET}"
    fi
    echo
    msg_success "Tudo pronto! Aproveite o seu novo ambiente de automação."
}

# --- PONTO DE ENTRADA DO SCRIPT ---
main