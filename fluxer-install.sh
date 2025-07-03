#!/bin/bash

# --- Definições de Cores e Estilos ---
# Usar tput para maior compatibilidade e para verificar se o terminal suporta cores.
if tput setaf 1 >&/dev/null; then
    VERDE=$(tput setaf 2; tput bold)
    AZUL=$(tput setaf 4; tput bold)
    AMARELO=$(tput setaf 3)
    VERMELHO=$(tput setaf 1; tput bold)
    NEGRITO=$(tput bold)
    RESET=$(tput sgr0)
else
    VERDE=""
    AZUL=""
    AMARELO=""
    VERMELHO=""
    NEGRITO=""
    RESET=""
fi

# --- Funções Modulares ---

# Exibe o banner inicial e as instruções de DNS.
display_banner() {
    clear
    echo -e "${AZUL}"
    echo "███████╗██╗      ██╗   ██ ██╗  ██╗███████╗██████╗     ███████╗███████╗████████╗██╗  ██╗██████╗ "
    echo "██╔════╝██║      ██║   ██ ║██║ ██╔╝██╔════╝██╔══██╗    ██╔════╝██╔════╝╚══██╔══╝██║  ██║██╔══██╗"
    echo "█████╗  ██║      ██║   ██ ║█████╔╝ █████╗  ██████╔╝    ███████╗█████╗     ██║   ██║  ██║██████╔╝"
    echo "██╔══╝  ██║      ██║   ██ ║██╔═██╗ ██╔══╝  ██╔══╝██    ╚════██║██╔══╝     ██║   ██║  ██║██╔═══╝ "
    echo "██      ███████╗╚██████╔╝██║  ██╗███████╗██║   ██    ███████║███████╗   ██║   ╚██████╔╝██║     "
    echo "╚═╝     ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝    ╚═╝   ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     "
    echo -e "${RESET}"
    echo -e "${VERDE}🛠 INSTALADOR FLUXER - CONFIGURAÇÃO COMPLETA DA VPS${RESET}"
    echo

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
}

# Coleta todas as entradas necessárias do usuário com validação.
get_user_input() {
    # Valida a entrada para garantir que não esteja vazia.
    while]; do
        read -p "🌐 Qual é o domínio principal (ex: fluxer.com.br): " DOMINIO_RAIZ
        if]; then
            echo -e "${VERMELHO}O domínio não pode ser vazio. Por favor, tente novamente.${RESET}"
        fi
    done

    while]; do
        read -s -p "🔑 Defina uma senha para o Portainer: " PORTAINER_PASSWORD
        echo
        if]; then
            echo -e "${VERMELHO}A senha do Portainer não pode ser vazia.${RESET}"
        fi
    done

    read -p "👤 Usuário root do MinIO (padrão: admin): " MINIO_ROOT_USER
    MINIO_ROOT_USER=${MINIO_ROOT_USER:-admin} # Define 'admin' como padrão se a entrada for vazia

    while]; do
        read -s -p "🔑 Defina uma senha para o MinIO: " MINIO_ROOT_PASSWORD
        echo
        if]; then
            echo -e "${VERMELHO}A senha do MinIO não pode ser vazia.${RESET}"
        fi
    done

    read -p "🔑 Chave da Evolution API (pressione Enter para gerar uma aleatória): " EVOLUTION_API_KEY_INPUT
    # Gera uma chave aleatória se o usuário não fornecer uma.
    if]; then
        EVOLUTION_API_KEY=$(openssl rand -hex 32)
        echo -e "${AMARELO}Nenhuma chave fornecida. Uma chave segura foi gerada para a Evolution API.${RESET}"
    else
        EVOLUTION_API_KEY="$EVOLUTION_API_KEY_INPUT"
    fi
}

# Gera o arquivo.env com base nas entradas coletadas.
generate_env_file() {
    echo -e "\n${AZUL}📄 Gerando arquivo.env...${RESET}"

    # Gera subdomínios automaticamente com base no domínio raiz.
    PORTAINER_DOMAIN="portainer.${DOMINIO_RAIZ}"
    N8N_EDITOR_DOMAIN="n8n.${DOMINIO_RAIZ}"
    N8N_WEBHOOK_DOMAIN="nwn.${DOMINIO_RAIZ}"
    TYPEBOT_EDITOR_DOMAIN="tpb.${DOMINIO_RAIZ}"
    TYPEBOT_VIEWER_DOMAIN="tpv.${DOMINIO_RAIZ}"
    MINIO_CONSOLE_DOMAIN="minio.${DOMINIO_RAIZ}"
    MINIO_S3_DOMAIN="s3.${DOMINIO_RAIZ}"
    EVOLUTION_DOMAIN="evo.${DOMINIO_RAIZ}"

    # Usa um Heredoc para criar o arquivo.env de uma só vez.
    # As variáveis são citadas para segurança e robustez.
    cat >.env <<EOF
# --- Rede e Certificados ---
REDE_DOCKER=fluxerNet
LE_EMAIL=fluxerautoma@gmail.com

# --- Portainer ---
PORTAINER_DOMAIN="${PORTAINER_DOMAIN}"
PORTAINER_PASSWORD="${PORTAINER_PASSWORD}"
PORTAINER_VOLUME=portainer_data

# --- PostgreSQL (usado por n8n e Typebot) ---
POSTGRES_PASSWORD=$(openssl rand -hex 16)
POSTGRES_VOLUME=postgres_data

# --- Redis (usado por n8n) ---
REDIS_VOLUME=redis_data
REDIS_URI=redis://redis:6379/8

# --- MinIO (Armazenamento S3) ---
MINIO_CONSOLE_DOMAIN="${MINIO_CONSOLE_DOMAIN}"
MINIO_S3_DOMAIN="${MINIO_S3_DOMAIN}"
MINIO_ROOT_USER="${MINIO_ROOT_USER}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD}"
MINIO_VOLUME=minio_data
S3_ENABLED=false
S3_ACCESS_KEY=
S3_SECRET_KEY=
S3_ENDPOINT="${MINIO_S3_DOMAIN}"

# --- n8n (Automação de Fluxos de Trabalho) ---
N8N_EDITOR_DOMAIN="${N8N_EDITOR_DOMAIN}"
N8N_WEBHOOK_DOMAIN="${N8N_WEBHOOK_DOMAIN}"
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
N8N_SMTP_USER=fluxerautoma@gmail.com
N8N_SMTP_PASS=teste

# --- Typebot (Construtor de Chatbot) ---
TYPEBOT_EDITOR_DOMAIN="${TYPEBOT_EDITOR_DOMAIN}"
TYPEBOT_VIEWER_DOMAIN="${TYPEBOT_VIEWER_DOMAIN}"
TYPEBOT_ENCRYPTION_KEY=$(openssl rand -hex 32)

# --- Evolution API ---
EVOLUTION_DOMAIN="${EVOLUTION_DOMAIN}"
EVOLUTION_API_KEY="${EVOLUTION_API_KEY}"
EVOLUTION_VOLUME=evolution_instances
EOF

    echo -e "${VERDE}✔.env criado com sucesso!${RESET}"
}

# Exibe um resumo final com URLs de acesso e informações importantes.
print_summary() {
    echo -e "\n${AZUL}${NEGRITO}✅ CONFIGURAÇÃO CONCLUÍDA!${RESET}"
    echo -e "${NEGRITO}Acesse seus serviços nos seguintes endereços:${RESET}"
    echo -e "${VERDE}Painel Portainer:     https://${PORTAINER_DOMAIN}${RESET}"
    echo -e "${VERDE}Painel n8n (editor):   https://${N8N_EDITOR_DOMAIN}${RESET}"
    echo -e "${VERDE}Webhook n8n:           https://${N8N_WEBHOOK_DOMAIN}${RESET}"
    echo -e "${VERDE}Builder Typebot:       https://${TYPEBOT_EDITOR_DOMAIN}${RESET}"
    echo -e "${VERDE}Viewer Typebot:        https://${TYPEBOT_VIEWER_DOMAIN}${RESET}"
    echo -e "${VERDE}MinIO Painel:          https://${MINIO_CONSOLE_DOMAIN}${RESET}"
    echo -e "${VERDE}MinIO S3 Endpoint:     https://${MINIO_S3_DOMAIN}${RESET}"
    echo -e "${VERDE}Evolution API:         https://${EVOLUTION_DOMAIN}${RESET}"
    echo

    echo -e "${AMARELO}${NEGRITO}⚠️ AVISO DE SEGURANÇA:${RESET}"
    echo -e "${AMARELO}As senhas e chaves que você definiu ou que foram geradas ${NEGRITO}NÃO${AMARELO} serão exibidas aqui."
    echo -e "${AMARELO}Certifique-se de tê-las armazenado em um local seguro (gerenciador de senhas).${RESET}"
    echo -e "${NEGRITO}Usuário root do MinIO:   ${MINIO_ROOT_USER}${RESET}"
    echo -e "${NEGRITO}Chave da Evolution API:  ${EVOLUTION_API_KEY}${RESET} ${AMARELO}(guarde esta chave!)${RESET}"
    echo
    echo -e "${AZUL}Para iniciar os serviços, execute o comando: ${NEGRITO}docker-compose up -d${RESET}"
}

# --- Função Principal de Execução ---
main() {
    display_banner
    get_user_input
    generate_env_file
    print_summary
}

# Executa o script
main