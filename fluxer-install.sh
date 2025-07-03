#!/bin/bash

#-------------------------------------------------------------------------------
# Script: Instalador Fluxer v2.0
# Descrição: Realiza a configuração completa de um ambiente de automação
#            com Portainer, n8n, Typebot, MinIO e Evolution API usando Docker.
# Autor: Seu Nome/Empresa
# Versão: 2.0
#-------------------------------------------------------------------------------

# === VARIÁVEIS DE CORES E ESTILOS ===
VERDE='\033[1;32m'
AZUL='\033[1;34m'
AMARELO='\033[1;33m'
VERMELHO='\033[1;31m'
NEGRITO='\033[1m'
RESET='\033[0m'

# === FUNÇÕES AUXILIARES PARA EXIBIR MENSAGENS ===
msg_header() {
    echo -e "\n${AZUL}${NEGRITO}# $1${RESET}"
}

msg_success() {
    echo -e "${VERDE}✔ $1${RESET}"
}

msg_info() {
    echo -e "${AZUL}➜ $1${RESET}"
}

msg_warning() {
    echo -e "${AMARELO}⚠️ $1${RESET}"
}

msg_error() {
    echo -e "${VERMELHO}❌ ERRO: $1${RESET}"
}

# === FUNÇÃO PRINCIPAL DE INSTALAÇÃO ===
main() {
    clear
    # --- BANNER ---
    echo -e "${AZUL}${NEGRITO}"
    echo "███████╗██╗      ██╗   ██╗██╗  ██╗███████╗██████╗      ███████╗███████╗████████╗██╗  ██╗██████╗ "
    echo "██╔════╝██║      ██║   ██║██║ ██╔╝██╔════╝██╔══██╗     ██╔════╝██╔════╝╚══██╔══╝██║  ██║██╔══██╗"
    echo "█████╗  ██║      ██║   ██║█████╔╝ █████╗  ██████╔╝     ███████╗█████╗     ██║   ██║  ██║██████╔╝"
    echo "██╔══╝  ██║      ██║   ██║██╔═██╗ ██╔══╝  ██╔══╝██     ╚════██║██╔══╝     ██║   ██║  ██║██╔═══╝ "
    echo "██║     ███████╗ ╚██████╔╝██║  ██╗███████╗██║   ██     ███████║███████╗   ██║   ╚██████╔╝██║     "
    echo "╚═╝     ╚══════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝    ██     ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     "
    echo -e "${RESET}"
    echo -e "${VERDE}${NEGRITO}🛠 INSTALADOR FLUXER - CONFIGURAÇÃO COMPLETA DA VPS${RESET}"

    # --- VERIFICAÇÃO DE DEPENDÊNCIAS ---
    msg_header "VERIFICANDO DEPENDÊNCIAS"
    if ! command -v docker &> /dev/null; then
        msg_error "Docker não encontrado. Por favor, instale o Docker e tente novamente."
        exit 1
    fi
    if ! command -v docker-compose &> /dev/null; then
        msg_error "Docker Compose não encontrado. Por favor, instale-o e tente novamente."
        exit 1
    fi
    if ! command -v openssl &> /dev/null; then
        msg_error "OpenSSL não encontrado. Por favor, instale-o e tente novamente."
        exit 1
    fi
    msg_success "Todas as dependências foram encontradas."

    # --- INSTRUÇÕES INICIAIS ---
    msg_header "CONFIGURAÇÃO DNS (WILDCARD)"
    msg_warning "Antes de continuar, configure um registro DNS WILDCARD na sua Cloudflare:"
    echo -e "${NEGRITO}  Tipo:   A"
    echo -e "  Nome:   *"
    echo -e "  IP:     (O IP desta VPS)"
    echo -e "  Proxy:  DNS only (nuvem cinza, desativado)${RESET}"
    echo
    read -p "Pressione [Enter] para continuar após configurar o DNS..."

    # --- COLETA DE DADOS DO USUÁRIO ---
    msg_header "COLETANDO INFORMAÇÕES"

    # Domínio Raiz
    while [[ -z "$DOMINIO_RAIZ" ]]; do
        read -p "🌐 Qual é o seu domínio principal (ex: seudominio.com.br): " DOMINIO_RAIZ
        if [[ -z "$DOMINIO_RAIZ" ]]; then
            msg_warning "O domínio não pode ser vazio."
        fi
    done

    # Email para Let's Encrypt
    while [[ -z "$LE_EMAIL" ]]; do
        read -p "📧 Email para o certificado SSL (Let's Encrypt): " LE_EMAIL
        if [[ -z "$LE_EMAIL" ]]; then
            msg_warning "O email não pode ser vazio."
        fi
    done

    # Credenciais do Portainer
    while true; do
        read -s -p "🔑 Digite uma senha para o Portainer: " PORTAINER_PASSWORD
        echo
        read -s -p "🔑 Confirme a senha do Portainer: " PORTAINER_PASSWORD_CONFIRM
        echo
        if [[ "$PORTAINER_PASSWORD" == "$PORTAINER_PASSWORD_CONFIRM" ]] && [[ -n "$PORTAINER_PASSWORD" ]]; then
            break
        else
            msg_warning "As senhas não coincidem ou estão vazias. Tente novamente."
        fi
    done

    # Credenciais do MinIO
    while [[ -z "$MINIO_ROOT_USER" ]]; do
        read -p "👤 Usuário root para o MinIO: " MINIO_ROOT_USER
    done
    while true; do
        read -s -p "🔑 Digite uma senha para o MinIO: " MINIO_ROOT_PASSWORD
        echo
        read -s -p "🔑 Confirme a senha do MinIO: " MINIO_ROOT_PASSWORD_CONFIRM
        echo
        if [[ "$MINIO_ROOT_PASSWORD" == "$MINIO_ROOT_PASSWORD_CONFIRM" ]] && [[ -n "$MINIO_ROOT_PASSWORD" ]]; then
            break
        else
            msg_warning "As senhas não coincidem ou estão vazias. Tente novamente."
        fi
    done

    # --- GERAÇÃO DE VARIÁVEIS E SUBDOMÍNIOS ---
    msg_header "GERANDO CONFIGURAÇÕES"
    msg_info "Gerando subdomínios e chaves de segurança..."

    # Subdomínios
    PORTAINER_DOMAIN="portainer.${DOMINIO_RAIZ}"
    N8N_EDITOR_DOMAIN="n8n.${DOMINIO_RAIZ}"
    N8N_WEBHOOK_DOMAIN="nwn.${DOMINIO_RAIZ}"
    TYPEBOT_EDITOR_DOMAIN="tpb.${DOMINIO_RAIZ}"
    TYPEBOT_VIEWER_DOMAIN="tpv.${DOMINIO_RAIZ}"
    MINIO_CONSOLE_DOMAIN="minio.${DOMINIO_RAIZ}"
    MINIO_S3_DOMAIN="s3.${DOMINIO_RAIZ}"
    EVOLUTION_DOMAIN="evo.${DOMINIO_RAIZ}"

    # Chaves e Senhas Aleatórias
    POSTGRES_PASSWORD=$(openssl rand -hex 16)
    N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
    TYPEBOT_ENCRYPTION_KEY=$(openssl rand -hex 16)
    EVOLUTION_API_KEY=$(openssl rand -hex 16)
    
    msg_success "Configurações geradas."

    # --- CRIAÇÃO DO ARQUIVO .ENV ---
    msg_info "Criando o arquivo de configuração .env..."
    # Usando cat com HEREDOC para criar o arquivo .env de uma só vez
    cat > .env <<EOF
# Gerado por Fluxer Installer v2.0 em $(date)

# --- GERAL ---
REDE_DOCKER=fluxerNet
LE_EMAIL=${LE_EMAIL}

# --- PORTAINER ---
PORTAINER_DOMAIN=${PORTAINER_DOMAIN}
PORTAINER_PASSWORD=${PORTAINER_PASSWORD}
PORTAINER_VOLUME=portainer_data

# --- BANCO DE DADOS (PostgreSQL) ---
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_VOLUME=postgres_data

# --- CACHE (Redis) ---
REDIS_VOLUME=redis_data
REDIS_URI=redis://redis:6379/8

# --- ARMAZENAMENTO (MinIO) ---
MINIO_CONSOLE_DOMAIN=${MINIO_CONSOLE_DOMAIN}
MINIO_S3_DOMAIN=${MINIO_S3_DOMAIN}
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
MINIO_VOLUME=minio_data

# --- N8N ---
N8N_EDITOR_DOMAIN=${N8N_EDITOR_DOMAIN}
N8N_WEBHOOK_DOMAIN=${N8N_WEBHOOK_DOMAIN}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
# Configure suas credenciais SMTP se necessário
N8N_SMTP_USER=
N8N_SMTP_PASS=
N8N_SMTP_HOST=
N8N_SMTP_PORT=587
N8N_SMTP_SSL=false

# --- TYPEBOT ---
TYPEBOT_EDITOR_DOMAIN=${TYPEBOT_EDITOR_DOMAIN}
TYPEBOT_VIEWER_DOMAIN=${TYPEBOT_VIEWER_DOMAIN}
TYPEBOT_ENCRYPTION_KEY=${TYPEBOT_ENCRYPTION_KEY}

# --- EVOLUTION API ---
EVOLUTION_DOMAIN=${EVOLUTION_DOMAIN}
EVOLUTION_API_KEY=${EVOLUTION_API_KEY}
EVOLUTION_VOLUME=evolution_instances
EOF
    msg_success "Arquivo .env criado com sucesso!"

    # --- INICIANDO OS SERVIÇOS ---
    msg_header "INICIANDO OS SERVIÇOS"
    if [ ! -f "docker-compose.yml" ]; then
        msg_error "Arquivo 'docker-compose.yml' não encontrado no diretório atual. O script não pode continuar."
        exit 1
    fi
    
    msg_info "Criando a rede Docker..."
    docker network create fluxerNet &> /dev/null
    
    msg_info "Iniciando os contêineres com 'docker-compose up -d'..."
    msg_warning "Este processo pode levar vários minutos, dependendo da sua conexão e VPS."
    if docker-compose up -d; then
        msg_success "Todos os serviços foram iniciados com sucesso!"
    else
        msg_error "Houve um problema ao iniciar os serviços com o Docker Compose."
        msg_warning "Verifique as mensagens de erro acima e o arquivo 'docker-compose.yml'."
        exit 1
    fi

    # --- RESUMO FINAL ---
    msg_header "🎉 INSTALAÇÃO CONCLUÍDA 🎉"
    echo -e "${VERDE}Aguarde alguns minutos para que todos os serviços e certificados SSL sejam configurados."
    echo -e "Abaixo estão os seus links de acesso:${RESET}"
    echo
    echo -e "${NEGRITO}Painel Portainer:   https://${PORTAINER_DOMAIN}${RESET}"
    echo -e "${NEGRITO}Painel n8n (editor):  https://${N8N_EDITOR_DOMAIN}${RESET}"
    echo -e "${NEGRITO}Webhook n8n:          https://${N8N_WEBHOOK_DOMAIN}${RESET}"
    echo -e "${NEGRITO}Builder Typebot:      https://${TYPEBOT_EDITOR_DOMAIN}${RESET}"
    echo -e "${NEGRITO}Viewer Typebot:       https://${TYPEBOT_VIEWER_DOMAIN}${RESET}"
    echo -e "${NEGRITO}MinIO Painel:         https://${MINIO_CONSOLE_DOMAIN}${RESET}"
    echo -e "${NEGRITO}MinIO S3 Endpoint:    ${MINIO_S3_DOMAIN}${RESET}"
    echo -e "${NEGRITO}Evolution API:        https://${EVOLUTION_DOMAIN}${RESET}"
    echo

    read -p "Você deseja exibir as senhas e chaves geradas agora? (s/N): " SHOW_CREDS
    if [[ "$SHOW_CREDS" =~ ^[Ss]$ ]]; then
        echo
        msg_header "CREDENCIAS GERADAS"
        echo -e "${AMARELO}Anote estas informações e guarde-as em um local seguro.${RESET}"
        echo -e "${NEGRITO}Senha do Portainer:      ${PORTAINER_PASSWORD}${RESET}"
        echo -e "${NEGRITO}Usuário root do MinIO:   ${MINIO_ROOT_USER}${RESET}"
        echo -e "${NEGRITO}Senha root do MinIO:     ${MINIO_ROOT_PASSWORD}${RESET}"
        echo -e "${NEGRITO}Chave da Evolution API:  ${EVOLUTION_API_KEY}${RESET}"
    fi
    echo
    msg_success "Tudo pronto! Aproveite seu novo ambiente de automação."
}

# --- PONTO DE ENTRADA DO SCRIPT ---
main
