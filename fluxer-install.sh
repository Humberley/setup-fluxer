#!/bin/bash

#-------------------------------------------------------------------------------
# Script: Instalador de Ambiente Fluxer
# Descrição: Coleta e VALIDA as informações do usuário, prepara o ambiente
#            e inicia os serviços de forma robusta.
# Autor: Humberley / [Seu Nome]
# Versão: 8.0 (Implementa método de verificação e criação de usuário robusto)
#-------------------------------------------------------------------------------

# === VARIÁVEIS DE CORES E ESTILOS ===
VERDE='\033[1;32m'
AZUL='\033[1;34m'
AMARELO='\033[1;33m'
VERMELHO='\033[1;31m'
NEGRITO='\033[1m'
RESET='\033[0m'

# === FUNÇÕES AUXILIARES E DE VALIDAÇÃO ===
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
    echo -e "\n${VERMELHO}❌ ERRO: $1${RESET}"
}
msg_fatal() {
    echo -e "\n${VERMELHO}❌ ERRO FATAL: $1${RESET}\n"
    exit 1
}

# Valida a senha com base em critérios de segurança
validate_password() {
    local password=$1
    local min_length=12
    local error_msg=""

    if [ ${#password} -lt $min_length ]; then
        error_msg+="\n- A senha precisa ter no mínimo ${min_length} caracteres."
    fi
    if ! [[ $password =~ [A-Z] ]]; then
        error_msg+="\n- A senha precisa conter pelo menos uma letra maiúscula."
    fi
    if ! [[ $password =~ [a-z] ]]; then
        error_msg+="\n- A senha precisa conter pelo menos uma letra minúscula."
    fi
    if ! [[ $password =~ [0-9] ]]; then
        error_msg+="\n- A senha precisa conter pelo menos um número."
    fi
    if ! [[ $password =~ [^a-zA-Z0-9] ]]; then
        error_msg+="\n- A senha precisa conter pelo menos um caractere especial (ex: @, #, !)."
    fi

    if [ -n "$error_msg" ]; then
        msg_warning "Senha inválida! Corrija os seguintes problemas:${error_msg}"
        return 1
    fi
    return 0
}

# Valida se a entrada é um domínio válido
validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        msg_warning "Formato de domínio inválido. Por favor, insira um domínio válido (ex: seudominio.com)."
        return 1
    fi
}

# Valida se a entrada é um e-mail válido
validate_email() {
    local email=$1
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$ ]]; then
        return 0
    else
        msg_warning "Formato de e-mail inválido. Por favor, insira um e-mail válido."
        return 1
    fi
}

# Valida se a entrada não contém espaços ou caracteres especiais perigosos
validate_simple_text() {
    local text=$1
    if [[ $text =~ [[:space:]] || ! $text =~ ^[a-zA-Z0-9_-]+$ ]]; then
        msg_warning "Entrada inválida. Não use espaços ou caracteres especiais (apenas letras, números, - e _)."
        return 1
    fi
    return 0
}

# Verifica a propagação do DNS
check_dns() {
    local domain_to_check=$1
    msg_header "VERIFICANDO PROPAGAÇÃO DNS PARA ${domain_to_check}"
    
    local public_ip
    public_ip=$(curl -s ifconfig.me)
    echo "IP Público desta VPS: ${public_ip}"
    echo "Aguardando ${domain_to_check} apontar para ${public_ip}..."

    local wait_time=0
    local max_wait=180

    while true; do
        local resolved_ip
        resolved_ip=$(dig +short "$domain_to_check" @1.1.1.1 | tail -n1)

        if [[ "$resolved_ip" == "$public_ip" ]]; then
            msg_success "DNS configurado corretamente!"
            break
        fi

        wait_time=$((wait_time + 10))
        if [ $wait_time -ge $max_wait ]; then
            msg_error "O domínio ${domain_to_check} não apontou para ${public_ip} após ${max_wait} segundos."
            msg_fatal "Verifique a sua configuração de DNS e tente novamente."
        fi
        
        printf "."
        sleep 10
    done
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
    if ! command -v envsubst &> /dev/null || ! command -v jq &> /dev/null || ! command -v dig &> /dev/null; then
        msg_fatal "Dependências não encontradas. Execute o script 'install.sh' primeiro."
    fi
    msg_success "Dependências prontas."

    # --- VERIFICAÇÃO DO DOCKER SWARM ---
    msg_header "VERIFICANDO AMBIENTE DOCKER SWARM"
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        msg_warning "Docker Swarm não está ativo. A inicializar..."
        docker swarm init || msg_fatal "Falha ao inicializar o Docker Swarm."
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

    # --- COLETA DE DADOS DO USUÁRIO COM VALIDAÇÃO ---
    msg_header "COLETANDO INFORMAÇÕES"

    while true; do
        read -p "🌐 Qual é o seu domínio principal (ex: seudominio.com.br): " DOMINIO_RAIZ < /dev/tty
        if validate_domain "$DOMINIO_RAIZ"; then break; fi
    done

    while true; do
        read -p "📧 Email para o certificado SSL (Let's Encrypt): " LE_EMAIL < /dev/tty
        if validate_email "$LE_EMAIL"; then break; fi
    done

    while true; do
        echo -e "${AMARELO}--> A senha deve ter no mínimo 12 caracteres, com maiúsculas, minúsculas, números e especiais.${RESET}"
        read -s -p "🔑 Digite uma senha para o Portainer: " PORTAINER_PASSWORD < /dev/tty; echo
        if validate_password "$PORTAINER_PASSWORD"; then
            read -s -p "🔑 Confirme a senha do Portainer: " PORTAINER_PASSWORD_CONFIRM < /dev/tty; echo
            if [[ "$PORTAINER_PASSWORD" == "$PORTAINER_PASSWORD_CONFIRM" ]]; then
                break
            else
                msg_warning "As senhas não coincidem. Tente novamente."
            fi
        fi
    done

    while true; do
        read -p "👤 Utilizador root para o MinIO (sem espaços ou especiais): " MINIO_ROOT_USER < /dev/tty
        if validate_simple_text "$MINIO_ROOT_USER"; then break; fi
    done
    
    while true; do
        echo -e "${AMARELO}--> A senha deve ter no mínimo 8 caracteres.${RESET}"
        read -s -p "🔑 Digite uma senha para o MinIO: " MINIO_ROOT_PASSWORD < /dev/tty; echo
        if [ ${#MINIO_ROOT_PASSWORD} -ge 8 ]; then
            read -s -p "🔑 Confirme a senha do MinIO: " MINIO_ROOT_PASSWORD_CONFIRM < /dev/tty; echo
            if [[ "$MINIO_ROOT_PASSWORD" == "$MINIO_ROOT_PASSWORD_CONFIRM" ]]; then
                break
            else
                msg_warning "As senhas não coincidem. Tente novamente."
            fi
        else
            msg_warning "A senha do MinIO precisa ter no mínimo 8 caracteres."
        fi
    done

    # --- GERAÇÃO DE VARIÁVEIS E VERIFICAÇÃO DE DNS ---
    msg_header "GERANDO CONFIGURAÇÕES E VERIFICANDO DNS"
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
    
    msg_success "Variáveis geradas."

    check_dns "${PORTAINER_DOMAIN}"

    # --- PREPARAÇÃO DO AMBIENTE SWARM ---
    msg_header "PREPARANDO O AMBIENTE SWARM"
    
    echo "Garantindo a existência da rede Docker overlay '${REDE_DOCKER}'..."
    docker network rm "$REDE_DOCKER" >/dev/null 2>&1
    if ! docker network create --driver=overlay --attachable "$REDE_DOCKER"; then
        msg_fatal "Falha ao criar a rede overlay '${REDE_DOCKER}'."
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

    # --- INICIANDO OS STACKS BASE ---
    msg_header "INICIANDO STACKS BASE (TRAEFIK E PORTAINER)"
    
    local STACKS_DIR="stacks"
    
    for stack_name in "traefik" "portainer"; do
        local template_file="${STACKS_DIR}/${stack_name}/${stack_name}.template.yml"
        if [ ! -f "$template_file" ]; then msg_warning "Ficheiro para '${stack_name}' não encontrado. A saltar."; continue; fi
        
        echo "-----------------------------------------------------"
        echo "Implantando o stack base: ${NEGRITO}${stack_name}${RESET}..."
        
        local processed_file="/tmp/${stack_name}.yml"
        envsubst < "$template_file" > "$processed_file"

        if docker stack deploy --compose-file "$processed_file" "$stack_name"; then
            msg_success "Stack '${stack_name}' implantado com sucesso!"
        else
            msg_fatal "Houve um problema ao implantar o stack '${stack_name}'. Verifique o ficheiro /tmp/${stack_name}.yml"
        fi
        rm "$processed_file"
    done

    # --- CONFIGURAR PORTAINER E OBTER CHAVE DE API (MÉTODO ROBUSTO) ---
    msg_header "CONFIGURANDO PORTAINER E GERANDO CHAVE DE API"
    echo "A aguardar que o Portainer fique online para criar o utilizador..."
    echo "Este processo pode demorar alguns minutos enquanto o certificado SSL é gerado."
    
    local max_retries=20 # 20 tentativas * 15s = 5 minutos
    local account_created=false

    for i in $(seq 1 $max_retries); do
        local init_response
        init_response=$(curl -s -k -w "%{http_code}" -X POST "https://${PORTAINER_DOMAIN}/api/users/admin/init" \
            -H "Content-Type: application/json" \
            --data "{\"Password\": \"${PORTAINER_PASSWORD}\"}")
        
        local http_code=${init_response: -3}
        
        if [[ "$http_code" == "200" ]]; then
            msg_success "Utilizador 'admin' do Portainer criado com sucesso!"
            account_created=true
            break
        else
            printf "."
            sleep 15
        fi
    done

    if [ "$account_created" = false ]; then
        msg_error "Não foi possível criar a conta de administrador no Portainer após ${max_retries} tentativas."
        echo "--- DIAGNÓSTICO ---"
        echo -e "${AMARELO}Verificando estado dos serviços...${RESET}"
        docker service ls
        echo -e "\n${AMARELO}--- Logs do Traefik (últimos 2 minutos) ---${RESET}"
        docker service logs --tail 100 --since 2m traefik_traefik
        echo -e "\n${AMARELO}--- Logs do Portainer (últimos 2 minutos) ---${RESET}"
        docker service logs --tail 50 --since 2m portainer_portainer
        msg_fatal "A instalação não pode continuar. Verifique os logs acima para encontrar a causa do problema."
    fi

    echo "A autenticar na API do Portainer para obter token JWT..."
    local jwt_response
    jwt_response=$(curl -s -k -X POST "https://${PORTAINER_DOMAIN}/api/auth" \
        -H "Content-Type: application/json" \
        --data "{\"username\": \"admin\", \"password\": \"${PORTAINER_PASSWORD}\"}")
    local PORTAINER_JWT=$(echo "$jwt_response" | jq -r .jwt)

    if [[ -z "$PORTAINER_JWT" || "$PORTAINER_JWT" == "null" ]]; then
        msg_fatal "Falha ao obter o token JWT do Portainer. Resposta: $jwt_response"
    fi
    msg_success "Token JWT obtido com sucesso."

    echo "A gerar chave de API do Portainer..."
    local apikey_response
    apikey_response=$(curl -s -k -X POST "https://${PORTAINER_DOMAIN}/api/users/admin/tokens" \
        -H "Authorization: Bearer ${PORTAINER_JWT}" \
        -H "Content-Type: application/json" \
        --data '{"description": "fluxer_installer_key"}')
    local PORTAINER_API_KEY=$(echo "$apikey_response" | jq -r .raw)

    if [[ -z "$PORTAINER_API_KEY" || "$PORTAINER_API_KEY" == "null" ]]; then
        msg_fatal "Falha ao gerar a chave de API do Portainer. Resposta: $apikey_response"
    fi
    msg_success "Chave de API do Portainer gerada e pronta para uso!"

    # --- ARMAZENAR CREDENCIAIS ---
    msg_header "ARMAZENANDO CREDENCIAIS PARA USO FUTURO"
    local DADOS_DIR="/root/dados_vps"
    mkdir -p "$DADOS_DIR"
    local DADOS_FILE="${DADOS_DIR}/dados_portainer"
    echo "Salvando credenciais do Portainer em ${DADOS_FILE}..."
    {
        echo "URL: https://${PORTAINER_DOMAIN}"
        echo "Username: admin"
        echo "Password: ${PORTAINER_PASSWORD}"
        echo "API_Key: ${PORTAINER_API_KEY}"
    } > "$DADOS_FILE"
    chmod 600 "$DADOS_FILE"
    msg_success "Credenciais salvas com sucesso."

    # --- IMPLANTAR STACKS DE APLICAÇÃO VIA API ---
    msg_header "IMPLANTANDO STACKS DE APLICAÇÃO VIA API DO PORTAINER"
    
    local PROCESSED_DIR="processed_stacks"
    mkdir -p "$PROCESSED_DIR"
    
    local DEPLOY_ORDER_API=("redis" "postgres" "minio" "n8n" "typebot" "evolution")
    local ENDPOINT_ID=1 # O endpoint local do Swarm é geralmente 1

    for stack_name in "${DEPLOY_ORDER_API[@]}"; do
        local template_file="${STACKS_DIR}/${stack_name}/${stack_name}.template.yml"
        local processed_file="${PROCESSED_DIR}/${stack_name}.yml"
        
        if [ ! -f "$template_file" ]; then msg_warning "Ficheiro para '${stack_name}' não encontrado. A saltar."; continue; fi

        echo "-----------------------------------------------------"
        echo "Processando e implantando o stack: ${NEGRITO}${stack_name}${RESET}..."
        
        envsubst < "$template_file" > "$processed_file"
        local COMPOSE_CONTENT=$(cat "$processed_file")

        local JSON_PAYLOAD
        JSON_PAYLOAD=$(jq -n \
            --arg name "$stack_name" \
            --arg content "$COMPOSE_CONTENT" \
            '{Name: $name, StackFileContent: $content}')

        local response
        response=$(curl -s -k -X POST \
            -H "X-API-Key: ${PORTAINER_API_KEY}" \
            -H "Content-Type: application/json" \
            --data-binary @- \
            "https://${PORTAINER_DOMAIN}/api/stacks?type=1&method=string&endpointId=${ENDPOINT_ID}" <<< "$JSON_PAYLOAD")

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
