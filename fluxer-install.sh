#!/bin/bash

#-------------------------------------------------------------------------------
# Script: Instalador de Ambiente Fluxer
# Descrição: Implementa a lógica de instalação robusta do SetupOrion,
#            com configurações YAML embutidas para máxima robustez.
# Autor: Humberley / [Seu Nome]
# Versão: 12.0 (Final - YAML Embutido)
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

# Função para aguardar um serviço estar com réplicas 1/1
wait_stack() {
    local stack_name=$1
    echo -e "\n${NEGRITO}Aguardando o serviço ${stack_name} ficar online...${RESET}"
    while true; do
        if docker service ls --filter "name=${stack_name}" | grep -q "1/1"; then
            msg_success "Serviço ${stack_name} está online."
            break
        fi
        printf "."
        sleep 10
    done
}

# Função para implantar um stack via API do Portainer
deploy_stack_via_api() {
    local stack_name=$1
    local compose_content=$2
    local api_key=$3
    local portainer_domain=$4
    local swarm_id=$5
    local endpoint_id=1
    local temp_file="/tmp/${stack_name}_deploy.yml"

    echo "-----------------------------------------------------"
    echo "Implantando o stack: ${NEGRITO}${stack_name}${RESET}..."

    # Salva o conteúdo gerado num ficheiro temporário
    echo -e "$compose_content" > "$temp_file"

    local response
    response=$(curl -s -k -w "\n%{http_code}" -X POST \
        -H "X-API-Key: ${api_key}" \
        -F "Name=${stack_name}" \
        -F "SwarmID=${swarm_id}" \
        -F "file=@${temp_file}" \
        "https://${portainer_domain}/api/stacks/create/swarm/file?endpointId=${endpoint_id}")
    
    rm "$temp_file" # Limpa o ficheiro temporário

    local http_code
    http_code=$(tail -n1 <<< "$response")
    local response_body
    response_body=$(sed '$ d' <<< "$response")

    if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
        msg_success "Stack '${stack_name}' implantado com sucesso via API do Portainer!"
        return 0
    else
        local error_message
        error_message=$(echo "$response_body" | jq -r '.message, .details' 2>/dev/null | tr '\n' ' ')
        msg_error "Falha ao implantar '${stack_name}' via API (Código: ${http_code}): ${error_message}"
        echo "Resposta completa da API: ${response_body}"
        return 1
    fi
}

# === FUNÇÕES DE GERAÇÃO DE YAML ===

generate_traefik_yml() {
cat << EOL
version: "3.7"
services:
  traefik:
    image: traefik:v3.0
    command:
      - "--api.dashboard=true"
      - "--providers.swarm=true"
      - "--providers.docker.endpoint=unix:///var/run/docker.sock"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=${REDE_DOCKER}"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--certificatesresolvers.letsencryptresolver.acme.email=${LE_EMAIL}"
      - "--certificatesresolvers.letsencryptresolver.acme.storage=/etc/traefik/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
      - "--log.level=DEBUG"
      - "--log.filePath=/var/log/traefik/traefik.log"
      - "--accesslog=true"
      - "--accesslog.filepath=/var/log/traefik/access.log"
    ports: [ "80:80", "443:443" ]
    volumes: [ "volume_swarm_certificates:/etc/traefik/letsencrypt", "/var/run/docker.sock:/var/run/docker.sock:ro", "volume_swarm_shared:/var/log/traefik" ]
    networks: [ ${REDE_DOCKER} ]
    deploy:
      placement:
        constraints: [ "node.role == manager" ]
networks:
  ${REDE_DOCKER}:
    external: true
volumes:
  volume_swarm_certificates:
    external: true
  volume_swarm_shared:
    external: true
EOL
}

generate_portainer_yml() {
cat << EOL
version: "3.7"
services:
  agent:
    image: portainer/agent:latest
    volumes: [ "/var/run/docker.sock:/var/run/docker.sock", "/var/lib/docker/volumes:/var/lib/docker/volumes" ]
    networks: [ ${REDE_DOCKER} ]
    deploy:
      mode: global
      placement: { constraints: [node.platform.os == linux] }
  portainer:
    image: portainer/portainer-ce:latest
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes: [ "portainer_data:/data" ]
    networks: [ ${REDE_DOCKER} ]
    deploy:
      mode: replicated
      replicas: 1
      placement: { constraints: [node.role == manager] }
      labels: [ "traefik.enable=true", "traefik.http.routers.portainer.rule=Host(\`${PORTAINER_DOMAIN}\`)", "traefik.http.routers.portainer.entrypoints=websecure", "traefik.http.routers.portainer.tls.certresolver=letsencryptresolver", "traefik.http.services.portainer.loadbalancer.server.port=9000", "traefik.docker.network=${REDE_DOCKER}" ]
volumes:
  portainer_data:
    external: true
networks:
  ${REDE_DOCKER}:
    external: true
EOL
}

generate_redis_yml() {
cat << EOL
version: "3.7"
services:
  redis:
    image: redis:latest
    command: [ "redis-server", "--appendonly", "yes", "--port", "6379" ]
    volumes:
      - redis_data:/data
    networks:
      - ${REDE_DOCKER}
    deploy:
      placement:
        constraints: [ "node.role == manager" ]
volumes:
  redis_data:
    external: true
    name: redis_data
networks:
  ${REDE_DOCKER}:
    external: true
EOL
}

generate_postgres_yml() {
cat << EOL
version: "3.7"
services:
  postgres:
    image: postgres:14
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - ${REDE_DOCKER}
    environment:
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - PG_MAX_CONNECTIONS=500
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [ "node.role == manager" ]
volumes:
  postgres_data:
    external: true
    name: postgres_data
networks:
  ${REDE_DOCKER}:
    external: true
EOL
}

generate_minio_yml() {
cat << EOL
version: "3.7"
services:
  minio:
    image: quay.io/minio/minio:latest
    command: server /data --console-address ":9001"
    volumes:
      - minio_data:/data
    networks:
      - ${REDE_DOCKER}
    environment:
      - MINIO_ROOT_USER=${MINIO_ROOT_USER}
      - MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
      - MINIO_BROWSER_REDIRECT_URL=https://${MINIO_CONSOLE_DOMAIN}
      - MINIO_SERVER_URL=https://${MINIO_S3_DOMAIN}
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [ "node.role == manager" ]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.minio_public.rule=Host(\`${MINIO_S3_DOMAIN}\`)"
        - "traefik.http.routers.minio_public.entrypoints=websecure"
        - "traefik.http.routers.minio_public.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.minio_public.loadbalancer.server.port=9000"
        - "traefik.http.routers.minio_console.rule=Host(\`${MINIO_CONSOLE_DOMAIN}\`)"
        - "traefik.http.routers.minio_console.entrypoints=websecure"
        - "traefik.http.routers.minio_console.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.minio_console.loadbalancer.server.port=9001"
volumes:
  minio_data:
    external: true
    name: minio_data
networks:
  ${REDE_DOCKER}:
    external: true
EOL
}

generate_n8n_yml() {
cat << EOL
version: "3.7"
services:
  n8n_editor:
    image: n8nio/n8n:latest
    command: start
    networks: [ ${REDE_DOCKER} ]
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=n8n_queue
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_HOST=${N8N_EDITOR_DOMAIN}
      - WEBHOOK_URL=https://${N8N_WEBHOOK_DOMAIN}/
      - GENERIC_TIMEZONE=America/Sao_Paulo
      - TZ=America/Sao_Paulo
      - QUEUE_BULL_REDIS_HOST=redis
      - N8N_SMTP_SENDER=${SMTP_USER}
      - N8N_SMTP_USER=${SMTP_USER}
      - N8N_SMTP_PASS=${SMTP_PASS}
      - N8N_SMTP_HOST=${SMTP_HOST}
      - N8N_SMTP_PORT=${SMTP_PORT}
      - N8N_SMTP_SSL=${SMTP_SSL}
    deploy:
      mode: replicated
      replicas: 1
      placement: { constraints: [ "node.role == manager" ] }
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.n8n_editor.rule=Host(\`${N8N_EDITOR_DOMAIN}\`)"
        - "traefik.http.routers.n8n_editor.entrypoints=websecure"
        - "traefik.http.routers.n8n_editor.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.n8n_editor.loadbalancer.server.port=5678"
  n8n_webhook:
    image: n8nio/n8n:latest
    command: webhook
    networks: [ ${REDE_DOCKER} ]
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=n8n_queue
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_HOST=${N8N_EDITOR_DOMAIN}
      - WEBHOOK_URL=https://${N8N_WEBHOOK_DOMAIN}/
      - GENERIC_TIMEZONE=America/Sao_Paulo
      - TZ=America/Sao_Paulo
      - QUEUE_BULL_REDIS_HOST=redis
    deploy:
      mode: replicated
      replicas: 1
      placement: { constraints: [ "node.role == manager" ] }
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.n8n_webhook.rule=Host(\`${N8N_WEBHOOK_DOMAIN}\`)"
        - "traefik.http.routers.n8n_webhook.entrypoints=websecure"
        - "traefik.http.routers.n8n_webhook.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.n8n_webhook.loadbalancer.server.port=5678"
  n8n_worker:
    image: n8nio/n8n:latest
    command: worker --concurrency=10
    networks: [ ${REDE_DOCKER} ]
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=n8n_queue
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - QUEUE_BULL_REDIS_HOST=redis
    deploy:
      mode: replicated
      replicas: 1
      placement: { constraints: [ "node.role == manager" ] }
networks:
  ${REDE_DOCKER}:
    external: true
EOL
}

generate_typebot_yml() {
cat << EOL
version: "3.7"
services:
  typebot_builder:
    image: baptistearno/typebot-builder:latest
    networks: [ ${REDE_DOCKER} ]
    environment:
      - DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/typebot
      - ENCRYPTION_SECRET=${TYPEBOT_ENCRYPTION_KEY}
      - NEXTAUTH_URL=https://${TYPEBOT_EDITOR_DOMAIN}
      - NEXT_PUBLIC_VIEWER_URL=https://${TYPEBOT_VIEWER_DOMAIN}
      - S3_ACCESS_KEY=${MINIO_ROOT_USER}
      - S3_SECRET_KEY=${MINIO_ROOT_PASSWORD}
      - S3_BUCKET=typebot
      - S3_ENDPOINT=${MINIO_S3_DOMAIN}
      - ADMIN_EMAIL=${SMTP_USER}
      - NEXT_PUBLIC_SMTP_FROM='Suporte <${SMTP_USER}>'
      - SMTP_AUTH_DISABLED=false
      - SMTP_USERNAME=${SMTP_USER}
      - SMTP_PASSWORD=${SMTP_PASS}
      - SMTP_HOST=${SMTP_HOST}
      - SMTP_PORT=${SMTP_PORT}
      - SMTP_SECURE=${SMTP_SSL}
    deploy:
      mode: replicated
      replicas: 1
      placement: { constraints: [ "node.role == manager" ] }
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.typebot_builder.rule=Host(\`${TYPEBOT_EDITOR_DOMAIN}\`)"
        - "traefik.http.routers.typebot_builder.entrypoints=websecure"
        - "traefik.http.routers.typebot_builder.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.typebot_builder.loadbalancer.server.port=3000"
  typebot_viewer:
    image: baptistearno/typebot-viewer:latest
    networks: [ ${REDE_DOCKER} ]
    environment:
      - DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/typebot
      - ENCRYPTION_SECRET=${TYPEBOT_ENCRYPTION_KEY}
      - NEXTAUTH_URL=https://${TYPEBOT_EDITOR_DOMAIN}
      - NEXT_PUBLIC_VIEWER_URL=https://${TYPEBOT_VIEWER_DOMAIN}
      - S3_ACCESS_KEY=${MINIO_ROOT_USER}
      - S3_SECRET_KEY=${MINIO_ROOT_PASSWORD}
      - S3_BUCKET=typebot
      - S3_ENDPOINT=${MINIO_S3_DOMAIN}
    deploy:
      mode: replicated
      replicas: 1
      placement: { constraints: [ "node.role == manager" ] }
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.typebot_viewer.rule=Host(\`${TYPEBOT_VIEWER_DOMAIN}\`)"
        - "traefik.http.routers.typebot_viewer.entrypoints=websecure"
        - "traefik.http.routers.typebot_viewer.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.typebot_viewer.loadbalancer.server.port=3000"
networks:
  ${REDE_DOCKER}:
    external: true
EOL
}

generate_evolution_yml() {
cat << EOL
version: "3.7"
services:
  evolution:
    image: atendai/evolution-api:latest
    volumes:
      - evolution_instances:/evolution/instances
    networks:
      - ${REDE_DOCKER}
    environment:
      - SERVER_URL=https://${EVOLUTION_DOMAIN}
      - AUTHENTICATION_API_KEY=${EVOLUTION_API_KEY}
      - AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true
      - DEL_INSTANCE=false
      - QRCODE_LIMIT=1902
      - LANGUAGE=pt-BR
      - CONFIG_SESSION_PHONE_VERSION=2.3000.1015901307
      - CONFIG_SESSION_PHONE_CLIENT=OrionDesign
      - CONFIG_SESSION_PHONE_NAME=Chrome
      - DATABASE_ENABLED=true
      - DATABASE_PROVIDER=postgresql
      - DATABASE_CONNECTION_URI=postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/evolution
      - DATABASE_CONNECTION_CLIENT_NAME=evolution
      - DATABASE_SAVE_DATA_INSTANCE=true
      - DATABASE_SAVE_DATA_NEW_MESSAGE=true
      - DATABASE_SAVE_MESSAGE_UPDATE=true
      - DATABASE_SAVE_DATA_CONTACTS=true
      - DATABASE_SAVE_DATA_CHATS=true
      - DATABASE_SAVE_DATA_LABELS=true
      - DATABASE_SAVE_DATA_HISTORIC=true
      - OPENAI_ENABLED=true
      - DIFY_ENABLED=true
      - TYPEBOT_ENABLED=true
      - TYPEBOT_API_VERSION=latest
      - CHATWOOT_ENABLED=true
      - CHATWOOT_MESSAGE_READ=true
      - CHATWOOT_MESSAGE_DELETE=true
      - CHATWOOT_IMPORT_DATABASE_CONNECTION_URI=postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/chatwoot?sslmode=disable
      - CACHE_REDIS_ENABLED=true
      - CACHE_REDIS_URI=redis://redis:6379
      - CACHE_REDIS_PREFIX_KEY=evolution
      - CACHE_REDIS_SAVE_INSTANCES=false
      - CACHE_LOCAL_ENABLED=false
      - S3_ENABLED=true
      - S3_ACCESS_KEY=${MINIO_ROOT_USER}
      - S3_SECRET_KEY=${MINIO_ROOT_PASSWORD}
      - S3_BUCKET=evolution
      - S3_PORT=443
      - S3_ENDPOINT=https://${MINIO_S3_DOMAIN}
      - S3_USE_SSL=true
      - WA_BUSINESS_TOKEN_WEBHOOK=evolution
      - WA_BUSINESS_URL=https://graph.facebook.com
      - WA_BUSINESS_VERSION=v20.0
      - WA_BUSINESS_LANGUAGE=pt_BR
      - TELEMETRY=false
      - TELEMETRY_URL=
      - WEBSOCKET_ENABLED=false
      - WEBSOCKET_GLOBAL_EVENTS=false
      - SQS_ENABLED=false
      - SQS_ACCESS_KEY_ID=
      - SQS_SECRET_ACCESS_KEY=
      - SQS_ACCOUNT_ID=
      - SQS_REGION=
      - RABBITMQ_ENABLED=false
      - RABBITMQ_URI=amqp://USER:PASS@rabbitmq:5672/evolution
      - RABBITMQ_EXCHANGE_NAME=evolution
      - RABBITMQ_GLOBAL_ENABLED=false
      - RABBITMQ_EVENTS_APPLICATION_STARTUP=false
      - RABBITMQ_EVENTS_MESSAGES_UPSERT=true
      - RABBITMQ_EVENTS_CONNECTION_UPDATE=true
      - WEBHOOK_GLOBAL_ENABLED=false
      - PROVIDER_ENABLED=false
      - PROVIDER_HOST=127.0.0.1
      - PROVIDER_PORT=5656
      - PROVIDER_PREFIX=evolution
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [ "node.role == manager" ]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.evolution.rule=Host(\`${EVOLUTION_DOMAIN}\`)"
        - "traefik.http.routers.evolution.entrypoints=websecure"
        - "traefik.http.routers.evolution.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.evolution.loadbalancer.server.port=8080"
volumes:
  evolution_instances:
    external: true
    name: evolution_instances
networks:
  ${REDE_DOCKER}:
    external: true
EOL
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

    # --- COLETA DE DADOS DO USUÁRIO COM VALIDAÇÃO ---
    msg_header "COLETANDO INFORMAÇÕES"
    while true; do read -p "🌐 Qual é o seu domínio principal (ex: seudominio.com.br): " DOMINIO_RAIZ < /dev/tty; if validate_domain "$DOMINIO_RAIZ"; then break; fi; done
    while true; do read -p "📧 Email para o certificado SSL (Let's Encrypt): " LE_EMAIL < /dev/tty; if validate_email "$LE_EMAIL"; then break; fi; done
    while true; do echo -e "${AMARELO}--> A senha deve ter no mínimo 12 caracteres, com maiúsculas, minúsculas, números e especiais.${RESET}"; read -s -p "🔑 Digite uma senha para o Portainer: " PORTAINER_PASSWORD < /dev/tty; echo; if validate_password "$PORTAINER_PASSWORD"; then read -s -p "🔑 Confirme a senha do Portainer: " PORTAINER_PASSWORD_CONFIRM < /dev/tty; echo; if [[ "$PORTAINER_PASSWORD" == "$PORTAINER_PASSWORD_CONFIRM" ]]; then break; else msg_warning "As senhas não coincidem."; fi; fi; done
    while true; do read -p "👤 Utilizador root para o MinIO (sem espaços ou especiais): " MINIO_ROOT_USER < /dev/tty; if validate_simple_text "$MINIO_ROOT_USER"; then break; fi; done
    while true; do echo -e "${AMARELO}--> A senha deve ter no mínimo 8 caracteres.${RESET}"; read -s -p "🔑 Digite uma senha para o MinIO: " MINIO_ROOT_PASSWORD < /dev/tty; echo; if [ ${#MINIO_ROOT_PASSWORD} -ge 8 ]; then read -s -p "🔑 Confirme a senha do MinIO: " MINIO_ROOT_PASSWORD_CONFIRM < /dev/tty; echo; if [[ "$MINIO_ROOT_PASSWORD" == "$MINIO_ROOT_PASSWORD_CONFIRM" ]]; then break; else msg_warning "As senhas não coincidem."; fi; else msg_warning "A senha do MinIO precisa ter no mínimo 8 caracteres."; fi; done
    msg_header "COLETANDO INFORMAÇÕES DE SMTP (para n8n e Typebot)"
    while true; do read -p "📧 Utilizador SMTP (ex: seuemail@gmail.com): " SMTP_USER < /dev/tty; if validate_email "$SMTP_USER"; then break; fi; done
    read -s -p "🔑 Senha SMTP (se for Gmail, use uma senha de aplicação): " SMTP_PASS < /dev/tty; echo
    read -p "🌐 Host SMTP (ex: smtp.gmail.com): " SMTP_HOST < /dev/tty
    read -p "🔢 Porta SMTP (ex: 587): " SMTP_PORT < /dev/tty
    read -p "🔒 Usar SSL para SMTP? (true/false): " SMTP_SSL < /dev/tty


    # --- GERAÇÃO DE VARIÁVEIS E VERIFICAÇÃO DE DNS ---
    msg_header "GERANDO CONFIGURAÇÕES E VERIFICANDO DNS"
    export DOMINIO_RAIZ LE_EMAIL PORTAINER_PASSWORD MINIO_ROOT_USER MINIO_ROOT_PASSWORD SMTP_USER SMTP_PASS SMTP_HOST SMTP_PORT SMTP_SSL
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
    
    export REDE_DOCKER="fluxerNet"
    msg_success "Variáveis geradas."

    check_dns "${PORTAINER_DOMAIN}"

    # --- PREPARAÇÃO DO AMBIENTE SWARM ---
    msg_header "PREPARANDO O AMBIENTE SWARM"
    echo "Garantindo a existência da rede Docker overlay '${REDE_DOCKER}'..."; docker network rm "$REDE_DOCKER" >/dev/null 2>&1; docker network create --driver=overlay --attachable "$REDE_DOCKER" || msg_fatal "Falha ao criar a rede overlay '${REDE_DOCKER}'."; msg_success "Rede '${REDE_DOCKER}' pronta."
    echo "Criando os volumes Docker..."; docker volume create "portainer_data" >/dev/null; docker volume create "volume_swarm_certificates" >/dev/null; docker volume create "volume_swarm_shared" >/dev/null; docker volume create "postgres_data" >/dev/null; docker volume create "redis_data" >/dev/null; docker volume create "minio_data" >/dev/null; docker volume create "evolution_instances" >/dev/null; msg_success "Volumes prontos."

    # --- ETAPA 1: INSTALAR TRAEFIK E PORTAINER ---
    msg_header "[1/4] INSTALANDO TRAEFIK E PORTAINER"
    
    echo "---"; echo "Implantando: ${NEGRITO}traefik${RESET}...";
    docker stack deploy --compose-file <(generate_traefik_yml) traefik || msg_fatal "Falha ao implantar Traefik."
    msg_success "Stack 'traefik' implantado."
    
    echo "---"; echo "Implantando: ${NEGRITO}portainer${RESET}...";
    docker stack deploy --compose-file <(generate_portainer_yml) portainer || msg_fatal "Falha ao implantar Portainer."
    msg_success "Stack 'portainer' implantado."

    # --- ETAPA 2: VERIFICAR SERVIÇOS E CONFIGURAR PORTAINER ---
    msg_header "[2/4] VERIFICANDO SERVIÇOS E CONFIGURANDO PORTAINER"
    wait_stack "traefik_traefik"
    wait_stack "portainer_portainer"
    
    echo "Aguardando 30 segundos para estabilização dos serviços..."; sleep 30

    echo "Tentando criar conta de administrador no Portainer..."; local max_retries=10; local account_created=false
    for i in $(seq 1 $max_retries); do
        local init_response; init_response=$(curl -s -k -w "\n%{http_code}" -X POST "https://${PORTAINER_DOMAIN}/api/users/admin/init" -H "Content-Type: application/json" --data "{\"Username\": \"admin\", \"Password\": \"${PORTAINER_PASSWORD}\"}"); local http_code=$(tail -n1 <<< "$init_response"); local response_body=$(sed '$ d' <<< "$init_response")
        if [[ "$http_code" == "200" ]]; then msg_success "Utilizador 'admin' do Portainer criado!"; account_created=true; break; else msg_warning "Tentativa ${i}/${max_retries} falhou."; echo "Código HTTP: ${http_code}"; echo "Resposta: ${response_body}"; echo "Aguardando 15s..."; sleep 15; fi
    done
    if [ "$account_created" = false ]; then msg_fatal "Não foi possível criar a conta de administrador no Portainer."; fi

    # --- ETAPA 3: OBTER CHAVE DE API ---
    msg_header "[3/4] OBTENDO CHAVE DE API DO PORTAINER"
    echo "A autenticar para obter token JWT..."; local jwt_response; jwt_response=$(curl -s -k -X POST "https://${PORTAINER_DOMAIN}/api/auth" -H "Content-Type: application/json" --data "{\"username\": \"admin\", \"password\": \"${PORTAINER_PASSWORD}\"}"); local PORTAINER_JWT=$(echo "$jwt_response" | jq -r .jwt); if [[ -z "$PORTAINER_JWT" || "$PORTAINER_JWT" == "null" ]]; then msg_fatal "Falha ao obter o token JWT."; fi; msg_success "Token JWT obtido."
    
    echo "Decodificando token para obter o ID do utilizador..."; local USER_ID; USER_ID=$(echo "$PORTAINER_JWT" | cut -d. -f2 | base64 --decode 2>/dev/null | jq -r .id); if [[ -z "$USER_ID" || "$USER_ID" == "null" ]]; then msg_fatal "Falha ao extrair o ID do utilizador do token JWT."; fi; msg_success "ID do utilizador 'admin' é: ${USER_ID}"

    echo "A gerar chave de API..."; local apikey_response; apikey_response=$(curl -s -k -X POST "https://${PORTAINER_DOMAIN}/api/users/${USER_ID}/tokens" -H "Authorization: Bearer ${PORTAINER_JWT}" -H "Content-Type: application/json" --data "{\"description\": \"fluxer_installer_key\", \"password\": \"${PORTAINER_PASSWORD}\"}"); local PORTAINER_API_KEY=$(echo "$apikey_response" | jq -r .rawAPIKey); if [[ -z "$PORTAINER_API_KEY" || "$PORTAINER_API_KEY" == "null" ]]; then msg_error "A resposta da API para criação da chave foi: $apikey_response"; msg_fatal "Falha ao gerar a chave de API."; fi; msg_success "Chave de API gerada!"

    echo "Obtendo Swarm ID..."; local ENDPOINT_ID=1; local SWARM_ID; SWARM_ID=$(curl -s -k -H "X-API-Key: ${PORTAINER_API_KEY}" "https://${PORTAINER_DOMAIN}/api/endpoints/${ENDPOINT_ID}/docker/swarm" | jq -r .ID); if [[ -z "$SWARM_ID" || "$SWARM_ID" == "null" ]]; then msg_fatal "Falha ao obter o Swarm ID."; fi; msg_success "Swarm ID obtido: ${SWARM_ID}"

    # --- ETAPA 4: IMPLANTAR STACKS DE APLICAÇÃO VIA API ---
    msg_header "[4/4] IMPLANTANDO STACKS DE APLICAÇÃO"
    
    deploy_stack_via_api "redis" "$(generate_redis_yml)" "$PORTAINER_API_KEY" "$PORTAINER_DOMAIN" "$SWARM_ID"
    deploy_stack_via_api "postgres" "$(generate_postgres_yml)" "$PORTAINER_API_KEY" "$PORTAINER_DOMAIN" "$SWARM_ID"
    deploy_stack_via_api "minio" "$(generate_minio_yml)" "$PORTAINER_API_KEY" "$PORTAINER_DOMAIN" "$SWARM_ID"
    deploy_stack_via_api "n8n" "$(generate_n8n_yml)" "$PORTAINER_API_KEY" "$PORTAINER_DOMAIN" "$SWARM_ID"
    deploy_stack_via_api "typebot" "$(generate_typebot_yml)" "$PORTAINER_API_KEY" "$PORTAINER_DOMAIN" "$SWARM_ID"
    deploy_stack_via_api "evolution" "$(generate_evolution_yml)" "$PORTAINER_API_KEY" "$PORTAINER_DOMAIN" "$SWARM_ID"

    # --- RESUMO FINAL ---
    msg_header "🎉 INSTALAÇÃO CONCLUÍDA 🎉"
    echo "Aguarde alguns minutos para que todos os serviços sejam iniciados."; echo "Pode verificar o estado no seu painel Portainer ou com o comando: ${NEGRITO}docker service ls${RESET}"; echo; echo "Abaixo estão os seus links de acesso:"; echo
    echo -e "${NEGRITO}Painel Portainer:   https://${PORTAINER_DOMAIN}${RESET}"
    echo -e "${NEGRITO}Painel n8n (editor):  https://${N8N_EDITOR_DOMAIN}${RESET}"
    echo -e "${NEGRITO}Builder Typebot:      https://${TYPEBOT_EDITOR_DOMAIN}${RESET}"
    echo -e "${NEGRITO}MinIO Painel:         https://${MINIO_CONSOLE_DOMAIN}${RESET}"
    echo -e "${NEGRITO}Evolution API:        https://${EVOLUTION_DOMAIN}${RESET}"
    echo
    read -p "Deseja exibir as senhas e chaves geradas? (s/N): " SHOW_CREDS < /dev/tty
    if [[ "$SHOW_CREDS" =~ ^[Ss]$ ]]; then
        echo; msg_header "CREDENCIAS GERADAS (guarde em local seguro)"
        echo -e "${NEGRITO}Senha do Portainer:      ${PORTAINER_PASSWORD}${RESET}"
        echo -e "${NEGRITO}Utilizador root do MinIO:   ${MINIO_ROOT_USER}${RESET}"
        echo -e "${NEGRITO}Senha root do MinIO:     ${MINIO_ROOT_PASSWORD}${RESET}"
        echo -e "${NEGRITO}Chave da Evolution API:  ${EVOLUTION_API_KEY}${RESET}"
    fi
    echo; msg_success "Tudo pronto! Aproveite o seu novo ambiente de automação."
}

# --- PONTO DE ENTRADA DO SCRIPT ---
main
