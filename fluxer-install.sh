#!/bin/bash

#-------------------------------------------------------------------------------
# Script: Instalador de Ambiente Fluxer
# Descrição: Coleta as informações do usuário, prepara o ambiente Docker Swarm
#            e inicia os serviços através da API do Portainer para gestão centralizada.
# Autor: Humberley / [Seu Nome]
# Versão: 4.7 (Adiciona Diagnóstico Automático)
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

    # --- VERIFICAÇÃO DE DEPENDÊNCIAS ---
    msg_header "VERIFICANDO DEPENDÊNCIAS"
    if ! command -v envsubst &> /dev/null; then
        msg_warning "Comando 'envsubst' não encontrado. A instalar 'gettext-base'..."
        apt-get update -qq && apt-get install -y gettext-base -qq || msg_error "Falha ao instalar 'gettext-base'."
    fi
    if ! command -v jq &> /dev/null; then
        msg_warning "Comando 'jq' não encontrado. A instalar..."
        apt-get update -qq && apt-get install -y jq -qq || msg_error "Falha ao instalar 'jq'."
    fi
    msg_success "Dependências prontas."

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
        read -s -p "🔑 Digite uma senha para o Portainer (mínimo 12 caracteres): " PORTAINER_PASSWORD < /dev/tty; echo
        read -s -p "🔑 Confirme a senha do Portainer: " PORTAINER_PASSWORD_CONFIRM < /dev/tty; echo
        if [[ "$PORTAINER_PASSWORD" == "$PORTAINER_PASSWORD_CONFIRM" ]] && [[ ${#PORTAINER_PASSWORD} -ge 12 ]]; then
            break
        else
            msg_warning "As senhas não coincidem ou têm menos de 12 caracteres. Tente novamente."
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

    # --- PREPARAÇÃO DO AMBIENTE SWARM ---
    msg_header "PREPARANDO O AMBIENTE SWARM"
    
    echo "Garantindo a existência da rede Docker overlay '${REDE_DOCKER}'..."
    docker network rm "$REDE_DOCKER" >/dev/null 2>&1
    if ! docker network create --driver=overlay --attachable "$REDE_DOCKER"; then
        msg_error "Falha ao criar a rede overlay '${REDE_DOCKER}'."
    fi
    msg_success "Rede '${REDE_DOCKER}' pronta."

    echo "Criando os volumes Docker (se não existirem)..."
    docker volume create "$PORTAINER_VOLUME" >/dev/null
    docker volume create "$POSTGRES_VOLUME" >/dev/null
    docker volume create "$REDIS_VOLUME" >/dev/null
    docker volume create "$MINIO_VOLUME" >/dev/null
    docker volume create "$EVOLUTION_VOLUME" >/dev/null
    docker volume create "volume_swarm_certificates" >/dev/null
    docker volume create "volume_swarm_shared" >/dev/null
    msg_success "Volumes prontos."

    # --- INICIANDO OS STACKS ---
    msg_header "INICIANDO OS STACKS DE SERVIÇOS"
    
    local STACKS_DIR="stacks"
    local PROCESSED_DIR="processed_stacks"
    mkdir -p "$PROCESSED_DIR"

    # Ordem de implantação: primeiro os serviços base via CLI, depois o resto via API
    local DEPLOY_ORDER_CLI=("traefik" "portainer")
    local DEPLOY_ORDER_API=("redis" "postgres" "minio" "n8n" "typebot" "evolution")

    # ETAPA 1: Implantar serviços base via CLI
    for stack_name in "${DEPLOY_ORDER_CLI[@]}"; do
        local template_file="${STACKS_DIR}/${stack_name}/${stack_name}.template.yml"
        local processed_file="${PROCESSED_DIR}/${stack_name}.yml"

        if [ ! -f "$template_file" ]; then msg_warning "Ficheiro para '${stack_name}' não encontrado. A saltar."; continue; fi
        
        echo "-----------------------------------------------------"
        echo "Processando e implantando o stack base: ${NEGRITO}${stack_name}${RESET}..."
        
        envsubst < "$template_file" > "$processed_file"

        if docker stack deploy --compose-file "$processed_file" "$stack_name"; then
            msg_success "Stack '${stack_name}' implantado com sucesso!"
        else
            msg_error "Houve um problema ao implantar o stack '${stack_name}'."
        fi
    done

    # ETAPA 2: Configurar Portainer e gerar chave de API automaticamente
    msg_header "CONFIGURANDO PORTAINER E GERANDO CHAVE DE API"
    echo "A aguardar que o Portainer fique online em https://${PORTAINER_DOMAIN}..."
    echo "Isto pode demorar alguns minutos enquanto o certificado SSL é gerado..."

    local wait_time=0
    local max_wait=180 # 3 minutos de tempo de espera

    until $(curl --output /dev/null --silent --head --fail -k "https://${PORTAINER_DOMAIN}/api/health"); do
        printf '.'
        sleep 5
        wait_time=$((wait_time + 5))
        if [ $wait_time -ge $max_wait ]; then
            echo # new line
            msg_error "O Portainer não ficou online após ${max_wait} segundos."
            echo "A exibir os logs dos serviços 'traefik' e 'portainer' para diagnóstico..."
            echo -e "\n${NEGRITO}------------------- LOGS DO TRAEFIK -------------------${RESET}"
            docker service logs traefik_traefik
            echo -e "\n${NEGRITO}------------------- LOGS DO PORTAINER -------------------${RESET}"
            docker service logs portainer_portainer
            echo -e "\n${AMARELO}------------------- POSSÍVEIS CAUSAS -------------------${RESET}"
            echo "1. O registo DNS Wildcard (*) não está a apontar corretamente para o IP desta VPS."
            echo "2. A Cloudflare está em modo Proxy (nuvem laranja). Deve estar em modo 'DNS Only' (nuvem cinza)."
            echo "3. O Let's Encrypt atingiu o limite de pedidos para o seu domínio. Tente novamente mais tarde."
            exit 1
        fi
    done
    echo -e "\n${VERDE}Portainer está online!${RESET}"

    echo "A criar utilizador 'admin' do Portainer..."
    curl -s -k -X POST "https://${PORTAINER_DOMAIN}/api/users/admin/init" \
        -H "Content-Type: application/json" \
        --data "{\"Password\": \"${PORTAINER_PASSWORD}\"}" > /dev/null

    echo "A autenticar na API do Portainer para obter token JWT..."
    local jwt_response=$(curl -s -k -X POST "https://${PORTAINER_DOMAIN}/api/auth" \
        -H "Content-Type: application/json" \
        --data "{\"username\": \"admin\", \"password\": \"${PORTAINER_PASSWORD}\"}")
    local PORTAINER_JWT=$(echo "$jwt_response" | jq -r .jwt)

    if [[ -z "$PORTAINER_JWT" || "$PORTAINER_JWT" == "null" ]]; then
        msg_error "Falha ao obter o token JWT do Portainer. Verifique a senha e o estado do serviço."
    fi
    msg_success "Token JWT obtido com sucesso."

    echo "A gerar chave de API do Portainer..."
    local apikey_response=$(curl -s -k -X POST "https://${PORTAINER_DOMAIN}/api/users/admin/tokens" \
        -H "Authorization: Bearer ${PORTAINER_JWT}" \
        -H "Content-Type: application/json" \
        --data '{"description": "fluxer_installer_key"}')
    local PORTAINER_API_KEY=$(echo "$apikey_response" | jq -r .raw)

    if [[ -z "$PORTAINER_API_KEY" || "$PORTAINER_API_KEY" == "null" ]]; then
        msg_error "Falha ao gerar a chave de API do Portainer."
    fi
    msg_success "Chave de API do Portainer gerada e pronta para uso!"

    # ETAPA 3: Implantar o resto dos stacks via API do Portainer
    msg_header "IMPLANTANDO STACKS DE APLICAÇÃO VIA API DO PORTAINER"
    local ENDPOINT_ID=1 # O endpoint local do Swarm é geralmente 1

    for stack_name in "${DEPLOY_ORDER_API[@]}"; do
        local template_file="${STACKS_DIR}/${stack_name}/${stack_name}.template.yml"
        local processed_file="${PROCESSED_DIR}/${stack_name}.yml"
        
        if [ ! -f "$template_file" ]; then msg_warning "Ficheiro para '${stack_name}' não encontrado. A saltar."; continue; fi

        echo "-----------------------------------------------------"
        echo "Processando e implantando o stack: ${NEGRITO}${stack_name}${RESET}..."
        
        envsubst < "$template_file" > "$processed_file"
        local COMPOSE_CONTENT=$(cat "$processed_file")

        # Cria o payload JSON para a API do Portainer
        local JSON_PAYLOAD=$(jq -n \
            --arg name "$stack_name" \
            --arg content "$COMPOSE_CONTENT" \
            '{Name: $name, StackFileContent: $content}')

        # Faz a chamada à API para criar o stack
        local response=$(curl -s -k -X POST \
            -H "X-API-Key: ${PORTAINER_API_KEY}" \
            -H "Content-Type: application/json" \
            --data-binary @- \
            "https://${PORTAINER_DOMAIN}/api/stacks?type=1&method=string&endpointId=${ENDPOINT_ID}" <<< "$JSON_PAYLOAD")

        # Verifica se a resposta contém um erro
        if echo "$response" | jq -e '.message' > /dev/null; then
            local error_message=$(echo "$response" | jq -r '.message')
            msg_error "Falha ao implantar '${stack_name}' via API: ${error_message}"
        else
            msg_success "Stack '${stack_name}' implantado com sucesso via API do Portainer!"
        fi
    done
    
    rm -rf "$PROCESSED_DIR"

    # --- RESUMO FINAL ---
    msg_header "🎉 INSTALAÇÃO CONCLUÍDA 🎉"
    echo "Aguarde alguns minutos para que todos os serviços sejam iniciados."
    echo "Pode verificar o estado no seu painel Portainer ou com o comando: ${NEGRITO}docker service ls${RESET}"
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
