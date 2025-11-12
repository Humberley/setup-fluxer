#!/bin/bash

#-------------------------------------------------------------------------------
# Script: Instalador de Ambiente Fluxer (Corrigido v8)
# Descrição: Implementa a lógica de instalação do SetupOrion,
#            com drop/criação de bancos de dados para garantir ambiente limpo.
# Autor: Humberley / Gemini
# Versão: 13.5 (UI e Instruções de DNS aprimoradas)
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
    local service_name=$2
    echo -e "\n${NEGRITO}Aguardando o serviço ${service_name} do stack ${stack_name} ficar online...${RESET}"
    local retries=30 # Adiciona um timeout para wait_stack
    while true; do
        if docker service ls --filter "name=${stack_name}_${service_name}" | grep -q "1/1"; then
            msg_success "Serviço ${stack_name}_${service_name} está online."
            break
        fi
        printf "."
        sleep 10
        ((retries--))
        if [ $retries -le 0 ]; then
            msg_fatal "Serviço ${stack_name}_${service_name} não ficou online a tempo após 300 segundos."
        fi
    done
}

# Função para implantar um stack via API do Portainer
deploy_stack_via_api() {
    local stack_name=$1
    local compose_content=$2
    local api_key=$3
    local portainer_host=$4  # pode ser domínio ou IP:porta
    local swarm_id=$5
    local endpoint_id=1
    local temp_file="/tmp/${stack_name}_deploy.yml"

    echo "-----------------------------------------------------"
    echo "Implantando o stack: ${NEGRITO}${stack_name}${RESET}..."

    # Determinar protocolo (HTTP para IPs locais, HTTPS para domínios)
    local protocol="https"
    if [[ "$portainer_host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        protocol="http"
        echo "Usando HTTP para IP: ${portainer_host}"
    else
        echo "Usando HTTPS para domínio: ${portainer_host}"
    fi

    # Salva o conteúdo gerado num ficheiro temporário
    echo -e "$compose_content" > "$temp_file"

    local response
    response=$(curl -s -k -w "\n%{http_code}" \
        --connect-timeout 15 \
        --max-time 30 \
        -X POST \
        -H "X-API-Key: ${api_key}" \
        -F "Name=${stack_name}" \
        -F "SwarmID=${swarm_id}" \
        -F "file=@${temp_file}" \
        "${protocol}://${portainer_host}/api/stacks/create/swarm/file?endpointId=${endpoint_id}")

    rm "$temp_file" # Limpa o ficheiro temporário

    local http_code
    http_code=$(tail -n1 <<< "$response" | tr -cd '0-9' | tail -c 3)
    local response_body
    response_body=$(sed '$ d' <<< "$response")

    if [[ "$http_code" == "200" ]] || [[ "$http_code" == "201" ]]; then
        msg_success "Stack '${stack_name}' implantado com sucesso via API!"
        return 0
    else
        local error_message
        error_message=$(echo "$response_body" | jq -r '.message, .details' 2>/dev/null | tr '\n' ' ')
        msg_error "Falha ao implantar '${stack_name}' (Código: ${http_code})"
        echo "Erro: ${error_message}"
        echo "URL usada: ${protocol}://${portainer_host}/api/stacks/create/swarm/file"
        echo "Resposta completa: ${response_body:0:500}"
        return 1
    fi
}

# === FUNÇÕES DE GERAÇÃO DE YAML ===

generate_traefik_yml() {
cat << EOL
version: "3.7"
services:
  traefik:
    image: traefik:v2.11.2
    command:
      - "--api.dashboard=true"
      - "--providers.docker.swarmMode=true"
      - "--providers.docker.endpoint=unix:///var/run/docker.sock"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=${REDE_DOCKER}"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--entrypoints.web.http.redirections.entrypoint.permanent=true"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.transport.respondingTimeouts.idleTimeout=3600"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencryptresolver.acme.storage=/etc/traefik/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencryptresolver.acme.email=${LE_EMAIL}"
      - "--log.level=DEBUG"
      - "--log.format=common"
      - "--log.filePath=/var/log/traefik/traefik.log"
      - "--accesslog=true"
      - "--accesslog.filepath=/var/log/traefik/access-log"

    volumes:
      - "vol_certificates:/etc/traefik/letsencrypt"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "vol_shared:/var/log/traefik"

    networks:
      - ${REDE_DOCKER}

    ports:
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host

    deploy:
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.middlewares.redirect-https.redirectscheme.scheme=https"
        - "traefik.http.middlewares.redirect-https.redirectscheme.permanent=true"
        - "traefik.http.routers.http-catchall.rule=Host(\`{host:.+}\`)"
        - "traefik.http.routers.http-catchall.entrypoints=web"
        - "traefik.http.routers.http-catchall.middlewares=redirect-https@docker"
        - "traefik.http.routers.http-catchall.priority=1"

volumes:
  vol_shared:
    external: true
    name: volume_swarm_shared
  vol_certificates:
    external: true
    name: volume_swarm_certificates

networks:
  ${REDE_DOCKER}:
    external: true
    attachable: true
    name: ${REDE_DOCKER}
EOL
}

generate_portainer_yml() {
cat << EOL
version: "3.7"
services:

  agent:
    image: portainer/agent:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - ${REDE_DOCKER}
    deploy:
      mode: global
      placement:
        constraints: [node.platform.os == linux]

  portainer:
    image: portainer/portainer-ce:latest
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - ${PORTAINER_VOLUME}:/data
    networks:
      - ${REDE_DOCKER}
    ports:
      - "9000:9000"
      - "9443:9443"
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.portainer.rule=Host(\`${PORTAINER_DOMAIN}\`)"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"
        - "traefik.http.routers.portainer.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.portainer.service=portainer"
        - "traefik.docker.network=${REDE_DOCKER}"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.priority=1"

volumes:
  ${PORTAINER_VOLUME}:
    external: true
    name: ${PORTAINER_VOLUME}

networks:
  ${REDE_DOCKER}:
    external: true
    attachable: true
    name: ${REDE_DOCKER}
EOL
}

generate_redis_yml() {
cat << EOL
version: "3.7"
services:
  redis:
    image: redis:latest
    command: [
        "redis-server",
        "--appendonly",
        "yes",
        "--port",
        "6379"
      ]

    volumes:
      - ${REDIS_VOLUME}:/data

    networks:
      - ${REDE_DOCKER}
      
    deploy:
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 2048M

volumes:
  ${REDIS_VOLUME}:
    external: true
    name: ${REDIS_VOLUME}

networks:
  ${REDE_DOCKER}:
    external: true
    name: ${REDE_DOCKER}
EOL
}

generate_postgres_yml() {
cat << EOL
version: "3.7"
services:
  postgres:
    image: postgres:14

    volumes:
      - ${POSTGRES_VOLUME}:/var/lib/postgresql/data

    networks:
      - ${REDE_DOCKER}

    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - PG_MAX_CONNECTIONS=500

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M

volumes:
  ${POSTGRES_VOLUME}:
    external: true
    name: ${POSTGRES_VOLUME}

networks:
  ${REDE_DOCKER}:
    external: true
    name: ${REDE_DOCKER}
EOL
}

generate_minio_yml() {
cat << EOL
version: "3.7"
services:

  minio:
    image: quay.io/minio/minio:RELEASE.2025-02-03T21-03-04Z-cpuv1
    command: server /data --console-address ":9001"

    volumes:
      - ${MINIO_VOLUME}:/data

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
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"

        # S3 público
        - "traefik.http.routers.minio_public.rule=Host(\`${MINIO_S3_DOMAIN}\`)"
        - "traefik.http.routers.minio_public.entrypoints=websecure"
        - "traefik.http.routers.minio_public.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.minio_public.loadbalancer.server.port=9000"
        - "traefik.http.services.minio_public.loadbalancer.passHostHeader=true"
        - "traefik.http.routers.minio_public.service=minio_public"

        # Console
        - "traefik.http.routers.minio_console.rule=Host(\`${MINIO_CONSOLE_DOMAIN}\`)"
        - "traefik.http.routers.minio_console.entrypoints=websecure"
        - "traefik.http.routers.minio_console.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.minio_console.loadbalancer.server.port=9001"
        - "traefik.http.services.minio_console.loadbalancer.passHostHeader=true"
        - "traefik.http.routers.minio_console.service=minio_console"

volumes:
  ${MINIO_VOLUME}:
    external: true
    name: ${MINIO_VOLUME}

networks:
  ${REDE_DOCKER}:
    external: true
    name: ${REDE_DOCKER}
EOL
}

generate_n8n_yml() {
cat << EOL
version: "3.7"
services:

  n8n_editor:
    image: n8nio/n8n:latest
    command: start
    networks:
      - ${REDE_DOCKER}
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=n8n_queue
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}

      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_HOST=${N8N_EDITOR_DOMAIN}
      - N8N_EDITOR_BASE_URL=https://${N8N_EDITOR_DOMAIN}/
      - WEBHOOK_URL=https://${N8N_WEBHOOK_DOMAIN}/
      - N8N_PROTOCOL=https

      - NODE_ENV=production
      - EXECUTIONS_MODE=queue
      - EXECUTIONS_TIMEOUT=3600
      - EXECUTIONS_TIMEOUT_MAX=7200
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true
      - N8N_RUNNERS_ENABLED=true
      - N8N_RUNNERS_MODE=internal

      - N8N_REINSTALL_MISSING_PACKAGES=true
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      - N8N_NODE_PATH=/home/node/.n8n/nodes
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true

      - N8N_SMTP_SENDER=${SMTP_USER}
      - N8N_SMTP_USER=${SMTP_USER}
      - N8N_SMTP_PASS=${SMTP_PASS}
      - N8N_SMTP_HOST=${SMTP_HOST}
      - N8N_SMTP_PORT=${SMTP_PORT}
      - N8N_SMTP_SSL=${SMTP_SSL}

      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=2

      - N8N_METRICS=true

      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=336

      - N8N_AI_ENABLED=false
      - N8N_AI_PROVIDER=openai
      - N8N_AI_OPENAI_API_KEY=

      - NODE_FUNCTION_ALLOW_BUILTIN=*
      - NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash

      - GENERIC_TIMEZONE=America/Sao_Paulo
      - TZ=America/Sao_Paulo
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.n8n_editor.rule=Host(\`${N8N_EDITOR_DOMAIN}\`)"
        - "traefik.http.routers.n8n_editor.entrypoints=websecure"
        - "traefik.http.routers.n8n_editor.priority=1"
        - "traefik.http.routers.n8n_editor.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.n8n_editor.service=n8n_editor"
        - "traefik.http.services.n8n_editor.loadbalancer.server.port=5678"
        - "traefik.http.services.n8n_editor.loadbalancer.passHostHeader=1"

  n8n_webhook:
    image: n8nio/n8n:latest
    command: webhook
    networks:
      - ${REDE_DOCKER}
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=n8n_queue
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}

      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_HOST=${N8N_EDITOR_DOMAIN}
      - N8N_EDITOR_BASE_URL=https://${N8N_EDITOR_DOMAIN}/
      - WEBHOOK_URL=https://${N8N_WEBHOOK_DOMAIN}/
      - N8N_PROTOCOL=https

      - NODE_ENV=production
      - EXECUTIONS_MODE=queue
      - EXECUTIONS_TIMEOUT=3600
      - EXECUTIONS_TIMEOUT_MAX=7200
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true
      - N8N_RUNNERS_ENABLED=true
      - N8N_RUNNERS_MODE=internal

      - N8N_REINSTALL_MISSING_PACKAGES=true
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      - N8N_NODE_PATH=/home/node/.n8n/nodes
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true

      - N8N_SMTP_SENDER=${SMTP_USER}
      - N8N_SMTP_USER=${SMTP_USER}
      - N8N_SMTP_PASS=${SMTP_PASS}
      - N8N_SMTP_HOST=${SMTP_HOST}
      - N8N_SMTP_PORT=${SMTP_PORT}
      - N8N_SMTP_SSL=${SMTP_SSL}

      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=2

      - N8N_METRICS=true

      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=336

      - N8N_AI_ENABLED=false
      - N8N_AI_PROVIDER=openai
      - N8N_AI_OPENAI_API_KEY=

      - NODE_FUNCTION_ALLOW_BUILTIN=*
      - NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash

      - GENERIC_TIMEZONE=America/Sao_Paulo
      - TZ=America/Sao_Paulo
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.n8n_webhook.rule=Host(\`${N8N_WEBHOOK_DOMAIN}\`)"
        - "traefik.http.routers.n8n_webhook.entrypoints=websecure"
        - "traefik.http.routers.n8n_webhook.priority=1"
        - "traefik.http.routers.n8n_webhook.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.n8n_webhook.service=n8n_webhook"
        - "traefik.http.services.n8n_webhook.loadbalancer.server.port=5678"
        - "traefik.http.services.n8n_webhook.loadbalancer.passHostHeader=1"

  n8n_worker:
    image: n8nio/n8n:latest
    command: worker --concurrency=10
    networks:
      - ${REDE_DOCKER}
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=n8n_queue
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}

      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_HOST=${N8N_EDITOR_DOMAIN}
      - N8N_EDITOR_BASE_URL=https://${N8N_EDITOR_DOMAIN}/
      - WEBHOOK_URL=https://${N8N_WEBHOOK_DOMAIN}/
      - N8N_PROTOCOL=https

      - NODE_ENV=production
      - EXECUTIONS_MODE=queue
      - EXECUTIONS_TIMEOUT=3600
      - EXECUTIONS_TIMEOUT_MAX=7200
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true
      - N8N_RUNNERS_ENABLED=true
      - N8N_RUNNERS_MODE=internal

      - N8N_REINSTALL_MISSING_PACKAGES=true
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      - N8N_NODE_PATH=/home/node/.n8n/nodes
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true

      - N8N_SMTP_SENDER=${SMTP_USER}
      - N8N_SMTP_USER=${SMTP_USER}
      - N8N_SMTP_PASS=${SMTP_PASS}
      - N8N_SMTP_HOST=${SMTP_HOST}
      - N8N_SMTP_PORT=${SMTP_PORT}
      - N8N_SMTP_SSL=${SMTP_SSL}

      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=2

      - N8N_METRICS=true

      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=336

      - N8N_AI_ENABLED=false
      - N8N_AI_PROVIDER=openai
      - N8N_AI_OPENAI_API_KEY=

      - NODE_FUNCTION_ALLOW_BUILTIN=*
      - NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash

      - GENERIC_TIMEZONE=America/Sao_Paulo
      - TZ=America/Sao_Paulo
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M

networks:
  ${REDE_DOCKER}:
    external: true
    name: ${REDE_DOCKER}
EOL
}

generate_typebot_yml() {
cat << EOL
version: "3.7"
services:

  typebot_builder:
    image: baptistearno/typebot-builder:latest
    networks:
      - ${REDE_DOCKER}
    environment:
      - DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/typebot
      - ENCRYPTION_SECRET=${TYPEBOT_ENCRYPTION_KEY}
      - DEFAULT_WORKSPACE_PLAN=UNLIMITED

      - NEXTAUTH_URL=https://${TYPEBOT_EDITOR_DOMAIN}
      - NEXT_PUBLIC_VIEWER_URL=https://${TYPEBOT_VIEWER_DOMAIN}
      - NEXTAUTH_URL_INTERNAL=http://localhost:3000

      - DISABLE_SIGNUP=false

      - ADMIN_EMAIL=${SMTP_USER}
      - NEXT_PUBLIC_SMTP_FROM='Suporte <${SMTP_USER}>'
      - SMTP_AUTH_DISABLED=false
      - SMTP_USERNAME=${SMTP_USER}
      - SMTP_PASSWORD=${SMTP_PASS}
      - SMTP_HOST=${SMTP_HOST}
      - SMTP_PORT=${SMTP_PORT}
      - SMTP_SECURE=${SMTP_SSL}

      - S3_ACCESS_KEY=${MINIO_ROOT_USER}
      - S3_SECRET_KEY=${MINIO_ROOT_PASSWORD}
      - S3_BUCKET=typebot
      - S3_ENDPOINT=${MINIO_S3_DOMAIN}

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M
      labels:
        - "io.portainer.accesscontrol.users=admin"
        - "traefik.enable=true"
        - "traefik.http.routers.typebot_builder.rule=Host(\`${TYPEBOT_EDITOR_DOMAIN}\`)"
        - "traefik.http.routers.typebot_builder.entrypoints=websecure"
        - "traefik.http.routers.typebot_builder.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.typebot_builder.loadbalancer.server.port=3000"
        - "traefik.http.services.typebot_builder.loadbalancer.passHostHeader=true"
        - "traefik.http.routers.typebot_builder.service=typebot_builder"

  typebot_viewer:
    image: baptistearno/typebot-viewer:latest
    networks:
      - ${REDE_DOCKER}
    environment:
      - DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/typebot
      - ENCRYPTION_SECRET=${TYPEBOT_ENCRYPTION_KEY}
      - DEFAULT_WORKSPACE_PLAN=UNLIMITED

      - NEXTAUTH_URL=https://${TYPEBOT_EDITOR_DOMAIN}
      - NEXT_PUBLIC_VIEWER_URL=https://${TYPEBOT_VIEWER_DOMAIN}
      - NEXTAUTH_URL_INTERNAL=http://localhost:3000

      - DISABLE_SIGNUP=false

      - ADMIN_EMAIL=${SMTP_USER}
      - NEXT_PUBLIC_SMTP_FROM='Suporte <${SMTP_USER}>'
      - SMTP_AUTH_DISABLED=false
      - SMTP_USERNAME=${SMTP_USER}
      - SMTP_PASSWORD=${SMTP_PASS}
      - SMTP_HOST=${SMTP_HOST}
      - SMTP_PORT=${SMTP_PORT}
      - SMTP_SECURE=${SMTP_SSL}

      - S3_ACCESS_KEY=${MINIO_ROOT_USER}
      - S3_SECRET_KEY=${MINIO_ROOT_PASSWORD}
      - S3_BUCKET=typebot
      - S3_ENDPOINT=${MINIO_S3_DOMAIN}

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M
      labels:
        - "io.portainer.accesscontrol.users=admin"
        - "traefik.enable=true"
        - "traefik.http.routers.typebot_viewer.rule=Host(\`${TYPEBOT_VIEWER_DOMAIN}\`)"
        - "traefik.http.routers.typebot_viewer.entrypoints=websecure"
        - "traefik.http.routers.typebot_viewer.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.typebot_viewer.loadbalancer.server.port=3000"
        - "traefik.http.services.typebot_viewer.loadbalancer.passHostHeader=true"
        - "traefik.http.routers.typebot_viewer.service=typebot_viewer"

networks:
  ${REDE_DOCKER}:
    external: true
    name: ${REDE_DOCKER}
EOL
}

generate_evolution_yml() {
cat << EOL
version: "3.7"
services:
  evolution:
    image: evoapicloud/evolution-api:latest
    volumes:
      - ${EVOLUTION_VOLUME}:/evolution/instances
    networks:
      - ${REDE_DOCKER}
    environment:
      # Configurações Gerais
      - SERVER_URL=https://${EVOLUTION_DOMAIN}
      - AUTHENTICATION_API_KEY=${EVOLUTION_API_KEY}
      - AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true
      - DEL_INSTANCE=false
      - QRCODE_LIMIT=1902
      - LANGUAGE=pt-BR
      
      # Configuração do Cliente
      - CONFIG_SESSION_PHONE_VERSION=2.3000.1023212226
      - CONFIG_SESSION_PHONE_CLIENT=OrionDesign
      - CONFIG_SESSION_PHONE_NAME=Chrome
      
      # Configuração do Banco de Dados
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
      
      # Integrações
      - OPENAI_ENABLED=true
      - DIFY_ENABLED=true
      - TYPEBOT_ENABLED=true
      - TYPEBOT_API_VERSION=latest
      - N8N_ENABLED=true
      - EVOAI_ENABLED=true
      
      # Integração com Chatwoot
      - CHATWOOT_ENABLED=true
      - CHATWOOT_MESSAGE_READ=true
      - CHATWOOT_MESSAGE_DELETE=true
      - CHATWOOT_IMPORT_DATABASE_CONNECTION_URI=postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/chatwoot?sslmode=disable
      - CHATWOOT_IMPORT_PLACEHOLDER_MEDIA_MESSAGE=false
      
      # Configuração do Cache
      - CACHE_REDIS_ENABLED=true
      - CACHE_REDIS_URI=redis://redis:6379/8
      - CACHE_REDIS_PREFIX_KEY=evolution
      - CACHE_REDIS_SAVE_INSTANCES=true
      - CACHE_LOCAL_ENABLED=true
      
      # Configuração do S3
      - S3_ENABLED=true
      - S3_ACCESS_KEY=${MINIO_ROOT_USER}
      - S3_SECRET_KEY=${MINIO_ROOT_PASSWORD}
      - S3_BUCKET=evolution
      - S3_PORT=443
      - S3_ENDPOINT=${MINIO_S3_DOMAIN}
      - S3_USE_SSL=true
      - S3_REGION=eu-south

      # Configuração do WhatsApp Business
      - WA_BUSINESS_TOKEN_WEBHOOK=evolution
      - WA_BUSINESS_URL=https://graph.facebook.com
      - WA_BUSINESS_VERSION=v21.0
      - WA_BUSINESS_LANGUAGE=pt_BR

      # Telemetria
      - TELEMETRY=false
      - TELEMETRY_URL=

      # Configuração do WebSocket
      - WEBSOCKET_ENABLED=false
      - WEBSOCKET_GLOBAL_EVENTS=false

      # Configuração do SQS
      - SQS_ENABLED=false
      - SQS_ACCESS_KEY_ID=
      - SQS_SECRET_ACCESS_KEY=
      - SQS_ACCOUNT_ID=
      - SQS_REGION=

      # Configuração do RabbitMQ
      - RABBITMQ_ENABLED=false
      - RABBITMQ_URI=amqp://USER:PASS@rabbitmq:5672/evolution
      - RABBITMQ_EXCHANGE_NAME=evolution
      - RABBITMQ_GLOBAL_ENABLED=false
      - RABBITMQ_EVENTS_APPLICATION_STARTUP=false
      - RABBITMQ_EVENTS_INSTANCE_CREATE=false
      - RABBITMQ_EVENTS_INSTANCE_DELETE=false
      - RABBITMQ_EVENTS_QRCODE_UPDATED=false
      - RABBITMQ_EVENTS_MESSAGES_SET=false
      - RABBITMQ_EVENTS_MESSAGES_UPSERT=true
      - RABBITMQ_EVENTS_MESSAGES_EDITED=false
      - RABBITMQ_EVENTS_MESSAGES_UPDATE=false
      - RABBITMQ_EVENTS_MESSAGES_DELETE=false
      - RABBITMQ_EVENTS_SEND_MESSAGE=false
      - RABBITMQ_EVENTS_CONTACTS_SET=false
      - RABBITMQ_EVENTS_CONTACTS_UPSERT=false
      - RABBITMQ_EVENTS_CONTACTS_UPDATE=false
      - RABBITMQ_EVENTS_PRESENCE_UPDATE=false
      - RABBITMQ_EVENTS_CHATS_SET=false
      - RABBITMQ_EVENTS_CHATS_UPSERT=false
      - RABBITMQ_EVENTS_CHATS_UPDATE=false
      - RABBITMQ_EVENTS_CHATS_DELETE=false
      - RABBITMQ_EVENTS_GROUPS_UPSERT=false
      - RABBITMQ_EVENTS_GROUP_UPDATE=false
      - RABBITMQ_EVENTS_GROUP_PARTICIPANTS_UPDATE=false
      - RABBITMQ_EVENTS_CONNECTION_UPDATE=true
      - RABBITMQ_EVENTS_CALL=false
      - RABBITMQ_EVENTS_TYPEBOT_START=false
      - RABBITMQ_EVENTS_TYPEBOT_CHANGE_STATUS=false

      # Configuração do Webhook
      - WEBHOOK_GLOBAL_ENABLED=false
      - WEBHOOK_GLOBAL_URL=false
      - WEBHOOK_GLOBAL_WEBHOOK_BY_EVENTS=false
      - WEBHOOK_EVENTS_APPLICATION_STARTUP=false
      - WEBHOOK_EVENTS_QRCODE_UPDATED=false
      - WEBHOOK_EVENTS_MESSAGES_SET=false
      - WEBHOOK_EVENTS_MESSAGES_UPSERT=false
      - WEBHOOK_EVENTS_MESSAGES_EDITED=false
      - WEBHOOK_EVENTS_MESSAGES_UPDATE=false
      - WEBHOOK_EVENTS_MESSAGES_DELETE=false
      - WEBHOOK_EVENTS_SEND_MESSAGE=false
      - WEBHOOK_EVENTS_CONTACTS_SET=false
      - WEBHOOK_EVENTS_CONTACTS_UPSERT=false
      - WEBHOOK_EVENTS_CONTACTS_UPDATE=false
      - WEBHOOK_EVENTS_PRESENCE_UPDATE=false
      - WEBHOOK_EVENTS_CHATS_SET=false
      - WEBHOOK_EVENTS_CHATS_UPSERT=false
      - WEBHOOK_EVENTS_CHATS_UPDATE=false
      - WEBHOOK_EVENTS_CHATS_DELETE=false
      - WEBHOOK_EVENTS_GROUPS_UPSERT=false
      - WEBHOOK_EVENTS_GROUPS_UPDATE=false
      - WEBHOOK_EVENTS_GROUP_PARTICIPANTS_UPDATE=false
      - WEBHOOK_EVENTS_CONNECTION_UPDATE=false
      - WEBHOOK_EVENTS_LABELS_EDIT=false
      - WEBHOOK_EVENTS_LABELS_ASSOCIATION=false
      - WEBHOOK_EVENTS_CALL=false
      - WEBHOOK_EVENTS_TYPEBOT_START=false
      - WEBHOOK_EVENTS_TYPEBOT_CHANGE_STATUS=false
      - WEBHOOK_EVENTS_ERRORS=false
      - WEBHOOK_EVENTS_ERRORS_WEBHOOK=
      - WEBHOOK_REQUEST_TIMEOUT_MS=60000
      - WEBHOOK_RETRY_MAX_ATTEMPTS=10
      - WEBHOOK_RETRY_INITIAL_DELAY_SECONDS=5
      - WEBHOOK_RETRY_USE_EXPONENTIAL_BACKOFF=true
      - WEBHOOK_RETRY_MAX_DELAY_SECONDS=300
      - WEBHOOK_RETRY_JITTER_FACTOR=0.2
      - WEBHOOK_RETRY_NON_RETRYABLE_STATUS_CODES=400,401,403,404,422
      
      # Configuração do Provider
      - PROVIDER_ENABLED=false
      - PROVIDER_HOST=127.0.0.1
      - PROVIDER_PORT=5656
      - PROVIDER_PREFIX=evolution
      
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=1"
        - "traefik.http.routers.evolution.rule=Host(\`${EVOLUTION_DOMAIN}\`)"
        - "traefik.http.routers.evolution.entrypoints=websecure"
        - "traefik.http.routers.evolution.priority=1"
        - "traefik.http.routers.evolution.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.evolution.service=evolution"
        - "traefik.http.services.evolution.loadbalancer.server.port=8080"
        - "traefik.http.services.evolution.loadbalancer.passHostHeader=true"

volumes:
  ${EVOLUTION_VOLUME}:
    external: true
    name: ${EVOLUTION_VOLUME}

networks:
  ${REDE_DOCKER}:
    external: true
    name: ${REDE_DOCKER}
EOL
}

# Gera um Docker Compose YAML contendo apenas o serviço n8n_editor
generate_n8n_editor_only_yml() {
cat << EOL
version: "3.7"
services:
  n8n_editor:
    image: n8nio/n8n:latest
    command: start
    networks:
      - ${REDE_DOCKER}
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=n8n_queue
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}

      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_HOST=${N8N_EDITOR_DOMAIN}
      - N8N_EDITOR_BASE_URL=https://${N8N_EDITOR_DOMAIN}/
      - WEBHOOK_URL=https://${N8N_WEBHOOK_DOMAIN}/
      - N8N_PROTOCOL=https

      - NODE_ENV=production
      - EXECUTIONS_MODE=queue
      - EXECUTIONS_TIMEOUT=3600
      - EXECUTIONS_TIMEOUT_MAX=7200
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true
      - N8N_RUNNERS_ENABLED=true
      - N8N_RUNNERS_MODE=internal

      - N8N_REINSTALL_MISSING_PACKAGES=true
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      - N8N_NODE_PATH=/home/node/.n8n/nodes
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true

      - N8N_SMTP_SENDER=${SMTP_USER}
      - N8N_SMTP_USER=${SMTP_USER}
      - N8N_SMTP_PASS=${SMTP_PASS}
      - N8N_SMTP_HOST=${SMTP_HOST}
      - N8N_SMTP_PORT=${SMTP_PORT}
      - N8N_SMTP_SSL=${SMTP_SSL}

      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=2

      - N8N_METRICS=true

      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=336

      - N8N_AI_ENABLED=false
      - N8N_AI_PROVIDER=openai
      - N8N_AI_OPENAI_API_KEY=

      - NODE_FUNCTION_ALLOW_BUILTIN=*
      - NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash

      - GENERIC_TIMEZONE=America/Sao_Paulo
      - TZ=America/Sao_Paulo
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.n8n_editor.rule=Host(\`${N8N_EDITOR_DOMAIN}\`)"
        - "traefik.http.routers.n8n_editor.entrypoints=websecure"
        - "traefik.http.routers.n8n_editor.priority=1"
        - "traefik.http.routers.n8n_editor.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.n8n_editor.service=n8n_editor"
        - "traefik.http.services.n8n_editor.loadbalancer.server.port=5678"
        - "traefik.http.services.n8n_editor.loadbalancer.passHostHeader=1"
networks:
  ${REDE_DOCKER}:
    external: true
    name: ${REDE_DOCKER}
EOL
}

# === FUNÇÕES DE CACHE ===
CACHE_FILE="/root/.fluxer-install-cache"

save_cache() {
    msg_header "SALVANDO CONFIGURAÇÕES EM CACHE"
    cat > "$CACHE_FILE" << EOF
# Cache de configuração Fluxer - $(date)
DOMINIO_RAIZ="${DOMINIO_RAIZ}"
LE_EMAIL="${LE_EMAIL}"
PORTAINER_PASSWORD="${PORTAINER_PASSWORD}"
MINIO_ROOT_USER="${MINIO_ROOT_USER}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD}"
SMTP_USER="${SMTP_USER}"
SMTP_PASS="${SMTP_PASS}"
EOF
    chmod 600 "$CACHE_FILE"
    msg_success "Configurações salvas em cache."
}

load_cache() {
    if [ -f "$CACHE_FILE" ]; then
        source "$CACHE_FILE"
        return 0
    fi
    return 1
}

clear_cache() {
    if [ -f "$CACHE_FILE" ]; then
        rm -f "$CACHE_FILE"
        msg_success "Cache limpo."
    fi
}

# Nova função para criar os bancos de dados
create_databases() {
    msg_header "REDEFININDO BANCOS DE DADOS NO POSTGRES"
    
    local postgres_container_id
    local retries=40 # Aumenta as tentativas para 200 segundos
    
    echo "Aguardando o container do Postgres ser criado..."
    while [[ -z "$postgres_container_id" && $retries -gt 0 ]]; do
        postgres_container_id=$(docker ps -q -f name=postgres_postgres)
        if [[ -z "$postgres_container_id" ]]; then
            printf "."
            sleep 5
            ((retries--))
        fi
    done

    if [[ -z "$postgres_container_id" ]]; then
        msg_fatal "Container do Postgres não foi encontrado após 200 segundos."
    fi
    
    msg_success "Container do Postgres encontrado: ${postgres_container_id}"
    
    echo "Aguardando o Postgres aceitar conexões..."
    retries=40 # Aumenta as tentativas para 200 segundos
    while ! docker exec "$postgres_container_id" pg_isready -U postgres &>/dev/null; do
        printf "."
        sleep 5
        ((retries--))
        if [ $retries -le 0 ]; then
            msg_fatal "Postgres não ficou pronto para aceitar conexões a tempo."
        fi
    done
    msg_success "Postgres está pronto!"

    # Adiciona uma pausa maior para garantir que o Postgres esteja totalmente estabilizado antes das operações de DB.
    echo "Pausa prolongada para estabilização completa do Postgres antes de redefinir bancos de dados..."
    sleep 20 # Aumentado o tempo de espera aqui para 20 segundos

    echo "Limpando e recriando banco de dados 'n8n_queue'..."
    docker exec "$postgres_container_id" psql -U postgres -c "DROP DATABASE IF EXISTS n8n_queue WITH (FORCE);"
    docker exec "$postgres_container_id" psql -U postgres -c "CREATE DATABASE n8n_queue;"
    
    echo "Limpando e recriando banco de dados 'typebot'..."
    docker exec "$postgres_container_id" psql -U postgres -c "DROP DATABASE IF EXISTS typebot WITH (FORCE);"
    docker exec "$postgres_container_id" psql -U postgres -c "CREATE DATABASE typebot;"

    echo "Limpando e recriando banco de dados 'evolution'..."
    docker exec "$postgres_container_id" psql -U postgres -c "DROP DATABASE IF EXISTS evolution WITH (FORCE);"
    docker exec "$postgres_container_id" psql -U postgres -c "CREATE DATABASE evolution;"
    
    msg_success "Bancos de dados redefinidos com sucesso."
}

# Função para configurar buckets do MinIO
setup_minio_buckets() {
    msg_header "CONFIGURANDO BUCKETS NO MINIO"

    echo "Aguardando MinIO estar totalmente pronto..."
    sleep 15

    echo "Criando alias para MinIO e buckets necessários..."

    # Usar docker run para executar comandos mc (MinIO Client)
    docker run --rm --network="${REDE_DOCKER}" \
        --entrypoint=/bin/sh \
        minio/mc:latest \
        -c "
        mc alias set myminio https://minio:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} --insecure && \
        mc mb myminio/typebot --ignore-existing --insecure && \
        mc mb myminio/evolution --ignore-existing --insecure && \
        mc anonymous set download myminio/typebot --insecure && \
        mc anonymous set download myminio/evolution --insecure && \
        echo 'Buckets criados com sucesso!'
        " || msg_error "Aviso: Falha ao configurar buckets MinIO. Configure manualmente depois."

    msg_success "Configuração do MinIO concluída."
}


# === FUNÇÃO PRINCIPAL ===
main() {
    # Verificar se usuário quer limpar cache manualmente
    if [[ "$1" == "--clear-cache" ]]; then
        clear_cache
        echo "Use 'bash fluxer-install.sh' para executar o instalador."
        exit 0
    fi

    clear
    # --- BANNER ---
    echo -e "${AZUL}${NEGRITO}"
    echo "███████╗██╗      ██╗    ██╗██╗  ██╗███████╗██████╗       ███████╗███████╗████████╗██╗  ██╗██████╗ "
    echo "██╔════╝██║      ██║    ██║██║ ██╔╝██╔════╝██╔══██╗      ██╔════╝██╔════╝╚══██╔══╝██║  ██║██╔══██╗"
    echo "█████╗  ██║      ██║    ██║█████╔╝ █████╗  ██████╔╝      ███████╗█████╗      ██║   ██║  ██║██████╔╝"
    echo "██╔══╝  ██║      ██║    ██║██╔═██╗ ██╔══╝  ██╔══╝██      ╚════██║██╔══╝      ██║   ██║  ██║██╔═══╝ "
    echo "██║     ███████╗ ╚██████╔╝██║  ██╗███████╗██║    ██      ███████║███████╗    ██║   ╚██████╔╝██║     "
    echo "╚═╝     ╚══════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝    ██      ╚══════╝╚══════╝    ╚═╝    ╚═════╝ ╚═╝     "
    echo -e "${RESET}"
    echo -e "${VERDE}${NEGRITO}🛠 INSTALADOR FLUXER - CONFIGURAÇÃO COMPLETA DA VPS (v13.5)${RESET}"
    echo -e "${AZUL}Criado por Humberley Cezilio${RESET}"
    echo -e "${AZUL}Instagram: https://www.instagram.com/humberley${RESET}"
    echo -e "${AZUL}Youtube: https://www.youtube.com/@Fluxer_ai${RESET}" # Nota: Link mantido conforme solicitado.

    # --- INSTRUÇÕES DE DNS ---
    msg_header "CONFIGURAÇÃO DE DNS (AÇÃO NECESSÁRIA)"
    echo -e "${AMARELO}Antes de continuar, é ${NEGRITO}ESSENCIAL${AMARELO} que você configure um DNS na sua Cloudflare."
    echo "Este script criará vários subdomínios (portainer, n8n, evo, etc)."
    echo "Para que todos funcionem, você precisa criar uma entrada do tipo 'A' Curinga (Wildcard)."
    echo ""
    echo -e "Acesse sua conta na ${NEGRITO}Cloudflare${RESET} e crie a seguinte entrada de DNS:"
    echo -e "  - ${NEGRITO}Tipo:${RESET}    A"
    echo -e "  - ${NEGRITO}Nome:${RESET}      * (apenas o asterisco)"
    echo -e "  - ${NEGRITO}Endereço IPv4:${RESET} $(curl -s ifconfig.me) (o IP desta VPS)"
    echo -e "  - ${NEGRITO}Proxy:${RESET}     ${VERMELHO}Desativado${RESET} (DNS Only - a nuvem deve ser cinza)"
    echo ""
    read -p "Após configurar o DNS na Cloudflare, pressione [Enter] para continuar..." < /dev/tty

    # --- VERIFICAR CACHE EXISTENTE ---
    local use_cache=false
    if load_cache; then
        msg_header "CONFIGURAÇÃO ANTERIOR ENCONTRADA"
        echo -e "${VERDE}Encontramos configurações de uma instalação anterior:${RESET}"
        echo "  🌐 Domínio: ${DOMINIO_RAIZ}"
        echo "  📧 Email: ${LE_EMAIL}"
        echo "  👤 Usuário MinIO: ${MINIO_ROOT_USER}"
        echo "  📧 SMTP: ${SMTP_USER}"
        echo ""
        read -p "Deseja usar essas configurações? (s/N): " use_cache_response < /dev/tty
        if [[ "$use_cache_response" =~ ^[Ss]$ ]]; then
            use_cache=true
            msg_success "Usando configurações salvas do cache."
        else
            msg_warning "Cache ignorado. Você precisará inserir as informações novamente."
            use_cache=false
        fi
    fi

    # --- COLETA DE DADOS DO USUÁRIO COM VALIDAÇÃO ---
    if [ "$use_cache" = false ]; then
        msg_header "COLETANDO INFORMAÇÕES"
        while true; do read -p "🌐 Qual é o seu domínio principal (ex: seudominio.com.br): " DOMINIO_RAIZ < /dev/tty; if validate_domain "$DOMINIO_RAIZ"; then break; fi; done
    while true; do read -p "📧 Email para o certificado SSL (Let's Encrypt): " LE_EMAIL < /dev/tty; if validate_email "$LE_EMAIL"; then break; fi; done
    while true; do echo -e "${AMARELO}--> A senha deve ter no mínimo 12 caracteres, com maiúsculas, minúsculas, números e especiais.${RESET}"; read -s -p "🔑 Digite uma senha para o Portainer: " PORTAINER_PASSWORD < /dev/tty; echo; if validate_password "$PORTAINER_PASSWORD"; then read -s -p "🔑 Confirme a senha do Portainer: " PORTAINER_PASSWORD_CONFIRM < /dev/tty; echo; if [[ "$PORTAINER_PASSWORD" == "$PORTAINER_PASSWORD_CONFIRM" ]]; then break; else msg_warning "As senhas não coincidem."; fi; fi; done
    while true; do read -p "👤 Utilizador root para o MinIO (sem espaços ou especiais): " MINIO_ROOT_USER < /dev/tty; if validate_simple_text "$MINIO_ROOT_USER"; then break; fi; done
    while true; do echo -e "${AMARELO}--> A senha do MinIO precisa ter no mínimo 8 caracteres.${RESET}"; read -s -p "🔑 Digite uma senha para o MinIO: " MINIO_ROOT_PASSWORD < /dev/tty; echo; if [ ${#MINIO_ROOT_PASSWORD} -ge 8 ]; then read -s -p "🔑 Confirme a senha do MinIO: " MINIO_ROOT_PASSWORD_CONFIRM < /dev/tty; echo; if [[ "$MINIO_ROOT_PASSWORD" == "$MINIO_ROOT_PASSWORD_CONFIRM" ]]; then break; else msg_warning "As senhas não coincidem."; fi; else msg_warning "A senha do MinIO precisa ter no mínimo 8 caracteres."; fi; done
    
        msg_header "COLETANDO INFORMAÇÕES DE SMTP (para n8n e Typebot)"
        echo -e "${AZUL}As configurações de SMTP do Gmail serão usadas por padrão.${RESET}"
        while true; do read -p "📧 Utilizador SMTP (seu e-mail do Gmail): " SMTP_USER < /dev/tty; if validate_email "$SMTP_USER"; then break; fi; done
        read -s -p "🔑 Senha SMTP (use uma 'Senha de App' gerada no Google): " SMTP_PASS < /dev/tty; echo

        # Salvar configurações no cache
        save_cache
    fi

    # --- GERAÇÃO DE VARIÁVEIS E VERIFICAÇÃO DE DNS ---
    msg_header "GERANDO CONFIGURAÇÕES E VERIFICANDO DNS"
    export DOMINIO_RAIZ LE_EMAIL PORTAINER_PASSWORD MINIO_ROOT_USER MINIO_ROOT_PASSWORD SMTP_USER SMTP_PASS
    export SMTP_HOST="smtp.gmail.com"
    export SMTP_PORT="587"
    export SMTP_SSL="true"

    # Variáveis SMTP para n8n e Typebot
    export N8N_SMTP_USER="${SMTP_USER}"
    export N8N_SMTP_PASS="${SMTP_PASS}"

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

    # Credenciais S3/MinIO geradas automaticamente
    export S3_ACCESS_KEY=$(openssl rand -hex 16)
    export S3_SECRET_KEY=$(openssl rand -hex 32)
    export S3_ENABLED="true"
    export S3_ENDPOINT="${MINIO_S3_DOMAIN}"

    # Redis URI
    export REDIS_URI="redis://redis:6379"

    export REDE_DOCKER="fluxerNet"

    export POSTGRES_VOLUME="postgres_data"
    export PORTAINER_VOLUME="portainer_data"
    export REDIS_VOLUME="redis_data"
    export MINIO_VOLUME="minio_data"
    export EVOLUTION_VOLUME="evolution_instances"
    
    msg_success "Variáveis geradas."

    check_dns "${PORTAINER_DOMAIN}"

    # --- PREPARAÇÃO DO AMBIENTE SWARM ---
    msg_header "PREPARANDO O AMBIENTE SWARM"

    # Remover todos os stacks ANTES de mexer na rede
    echo "Removendo stacks antigos (se existirem)..."
    docker stack rm traefik portainer redis postgres minio n8n typebot evolution >/dev/null 2>&1
    echo "Aguardando 30 segundos para stacks serem removidos completamente..."
    sleep 30

    # Agora é seguro recriar a rede
    echo "Garantindo a existência da rede Docker overlay '${REDE_DOCKER}'..."
    if docker network inspect "$REDE_DOCKER" >/dev/null 2>&1; then
        msg_success "Rede '${REDE_DOCKER}' já existe e será reutilizada."
    else
        docker network create --driver=overlay --attachable "$REDE_DOCKER" || msg_fatal "Falha ao criar a rede overlay '${REDE_DOCKER}'."
        msg_success "Rede '${REDE_DOCKER}' criada com sucesso."
    fi

    # Limpar volumes antigos
    echo "Limpando volumes de banco de dados para garantir ambiente limpo..."
    docker volume rm "${POSTGRES_VOLUME}" >/dev/null 2>&1
    sleep 5

    # Criar volumes necessários
    echo "Criando volumes Docker..."
    docker volume create "portainer_data" >/dev/null 2>&1
    docker volume create "volume_swarm_certificates" >/dev/null 2>&1
    docker volume create "volume_swarm_shared" >/dev/null 2>&1
    docker volume create "${POSTGRES_VOLUME}" >/dev/null 2>&1
    docker volume create "${REDIS_VOLUME}" >/dev/null 2>&1
    docker volume create "${MINIO_VOLUME}" >/dev/null 2>&1
    docker volume create "${EVOLUTION_VOLUME}" >/dev/null 2>&1
    msg_success "Ambiente preparado e volumes criados."

    # --- ETAPA 1: INSTALAR TRAEFIK E PORTAINER ---
    msg_header "[1/5] INSTALANDO TRAEFIK E PORTAINER"
    
    echo "---"; echo "Implantando: ${NEGRITO}traefik${RESET}...";
    docker stack deploy --compose-file <(echo "$(generate_traefik_yml)") traefik || msg_fatal "Falha ao implantar Traefik."
    msg_success "Stack 'traefik' implantado."
    
    echo "---"; echo "Implantando: ${NEGRITO}portainer${RESET}...";
    docker stack deploy --compose-file <(echo "$(generate_portainer_yml)") portainer || msg_fatal "Falha ao implantar Portainer."
    msg_success "Stack 'portainer' implantado."

    # --- ETAPA 2: VERIFICAR SERVIÇOS E CONFIGURAR PORTAINER ---
    msg_header "[2/5] VERIFICANDO SERVIÇOS E CONFIGURANDO PORTAINER"
    wait_stack "traefik" "traefik"
    wait_stack "portainer" "portainer"

    echo "Aguardando 15 segundos para estabilização inicial..."
    sleep 15

    # === DIAGNÓSTICO INICIAL ROBUSTO ===
    echo -e "\n${NEGRITO}Executando diagnóstico inicial do Portainer...${RESET}"

    # Obter container ID real (não service)
    echo -e "\n1. Identificando container Portainer..."
    local PORTAINER_CONTAINER_ID
    PORTAINER_CONTAINER_ID=$(docker ps --filter "name=portainer_portainer" --format "{{.ID}}" | head -n1)

    if [ -z "$PORTAINER_CONTAINER_ID" ]; then
        msg_warning "Não foi possível encontrar container do Portainer em execução."
        echo "Listando todos containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.ID}}"
        msg_fatal "Container do Portainer não está em execução."
    fi

    echo "Container ID: ${PORTAINER_CONTAINER_ID}"

    # Status detalhado do container
    echo -e "\n2. Status do container:"
    docker inspect "$PORTAINER_CONTAINER_ID" --format 'Estado: {{.State.Status}} | Saúde: {{.State.Health.Status}} | PID: {{.State.Pid}}'

    # Obter IPs do container
    echo -e "\n3. IPs do container Portainer:"
    local CONTAINER_IP_PRIMARY
    local CONTAINER_IP_SECONDARY
    CONTAINER_IP_PRIMARY=$(docker inspect "$PORTAINER_CONTAINER_ID" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | awk '{print $1}')
    CONTAINER_IP_SECONDARY=$(docker service inspect portainer_portainer --format '{{range .Endpoint.VirtualIPs}}{{.Addr}}{{end}}' 2>/dev/null | cut -d'/' -f1 | head -n1)

    echo "IP Primário (container): ${CONTAINER_IP_PRIMARY}"
    echo "IP Secundário (overlay): ${CONTAINER_IP_SECONDARY}"

    # Logs usando container ID direto
    echo -e "\n4. Logs do container (últimas 10 linhas):"
    docker logs "$PORTAINER_CONTAINER_ID" --tail 10 --since 60s 2>&1 || echo "Não foi possível obter logs do container"

    # Verificar portas
    echo -e "\n5. Portas publicadas:"
    docker port "$PORTAINER_CONTAINER_ID" 2>/dev/null || echo "Nenhuma porta mapeada"

    echo -e "\n6. Portas listening no host:"
    (netstat -tulpn 2>/dev/null || ss -tulpn 2>/dev/null) | grep -E "(9000|9443)" || echo "Portas 9000/9443 não encontradas"

    # === VERIFICAÇÃO 1: AGUARDAR "starting HTTP server" NOS LOGS ===
    echo -e "\n${NEGRITO}[Verificação 1/5]${RESET} Aguardando Portainer iniciar servidor HTTP..."
    echo "Monitorando logs do container até ver 'starting HTTP server'..."
    local log_retries=60
    local http_log_found=false

    while [ $log_retries -gt 0 ]; do
        # Usar docker logs com container ID real
        if docker logs "$PORTAINER_CONTAINER_ID" --tail 50 --since 120s 2>&1 | grep -q "starting HTTP server"; then
            msg_success "Portainer iniciou o servidor HTTP (confirmado via logs)."
            http_log_found=true
            break
        fi

        # Debug a cada 10 tentativas
        if [ $((log_retries % 10)) -eq 0 ]; then
            echo -e "\n  [Debug] Aguardando 'starting HTTP server' (tentativa $((60 - log_retries + 1))/60)"
            echo "  Últimas 3 linhas do log:"
            docker logs "$PORTAINER_CONTAINER_ID" --tail 3 2>&1 | sed 's/^/    /'
        else
            printf "."
        fi

        sleep 2
        ((log_retries--))
    done
    echo ""

    if [ "$http_log_found" = false ]; then
        msg_warning "Não detectamos 'starting HTTP server' nos logs após 120 segundos."
        echo "Logs completos do container:"
        docker logs "$PORTAINER_CONTAINER_ID" --tail 30 2>&1
        msg_fatal "Portainer não está inicializando corretamente."
    fi

    # Aguardar tempo adicional para API estar pronta
    echo "Aguardando 15 segundos para API ficar operacional..."
    sleep 15

    # === VERIFICAÇÃO 2: ESTRATÉGIA MULTI-ENDPOINT PARA ACESSAR PORTAINER ===
    echo -e "\n${NEGRITO}[Verificação 2/5]${RESET} Testando conectividade com Portainer usando múltiplas estratégias..."

    # Preparar lista de endpoints para testar
    local PORTAINER_ENDPOINTS=()
    local PORTAINER_WORKING_ENDPOINT=""

    # Estratégia 1: IP direto do container (mais confiável, sem dependências)
    if [ -n "$CONTAINER_IP_PRIMARY" ]; then
        PORTAINER_ENDPOINTS+=("http://${CONTAINER_IP_PRIMARY}:9000")
    fi
    if [ -n "$CONTAINER_IP_SECONDARY" ] && [ "$CONTAINER_IP_SECONDARY" != "$CONTAINER_IP_PRIMARY" ]; then
        PORTAINER_ENDPOINTS+=("http://${CONTAINER_IP_SECONDARY}:9000")
    fi

    # Estratégia 2: localhost com IPv4 explícito
    PORTAINER_ENDPOINTS+=("http://127.0.0.1:9000")

    # Estratégia 3: localhost padrão
    PORTAINER_ENDPOINTS+=("http://localhost:9000")

    # Estratégia 4: Domínio via Traefik (apenas se DNS estiver configurado)
    # Não adicionar por enquanto, testar apenas se outros falharem

    echo "Endpoints a serem testados:"
    for idx in "${!PORTAINER_ENDPOINTS[@]}"; do
        echo "  $((idx + 1)). ${PORTAINER_ENDPOINTS[$idx]}"
    done

    # Função para testar um endpoint
    test_portainer_endpoint() {
        local endpoint="$1"
        local test_path="${2:-/}"

        # Testar conteúdo HTML
        local html_response
        html_response=$(curl -s --connect-timeout 5 --max-time 10 "${endpoint}${test_path}" 2>/dev/null)

        if [[ -n "$html_response" ]] && [[ "$html_response" =~ [a-zA-Z] ]]; then
            return 0  # Sucesso
        fi

        # Testar código HTTP
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "${endpoint}${test_path}" 2>/dev/null)

        if [[ "$http_code" =~ ^[2-5][0-9][0-9]$ ]]; then
            return 0  # Sucesso
        fi

        return 1  # Falha
    }

    # Tentar cada endpoint
    local endpoint_found=false
    local max_attempts_per_endpoint=10

    for endpoint in "${PORTAINER_ENDPOINTS[@]}"; do
        echo -e "\n${NEGRITO}Testando: ${endpoint}${RESET}"

        for attempt in $(seq 1 $max_attempts_per_endpoint); do
            if test_portainer_endpoint "$endpoint" "/"; then
                msg_success "Endpoint funcionando: ${endpoint}"
                PORTAINER_WORKING_ENDPOINT="$endpoint"
                endpoint_found=true
                break 2  # Sai dos dois loops
            fi

            if [ $attempt -eq 5 ]; then
                echo "  Tentativa 5/${max_attempts_per_endpoint} - ainda testando..."
            else
                printf "."
            fi

            sleep 2
        done

        msg_warning "Endpoint não respondeu após ${max_attempts_per_endpoint} tentativas."
    done

    echo ""

    if [ "$endpoint_found" = false ]; then
        msg_error "Nenhum endpoint do Portainer respondeu após testar todas as estratégias."
        echo -e "\n${AMARELO}=== DIAGNÓSTICO DETALHADO ===${RESET}"

        echo -e "\n1. Status do container:"
        docker inspect "$PORTAINER_CONTAINER_ID" --format 'Estado: {{.State.Status}} | PID: {{.State.Pid}} | Reinícios: {{.RestartCount}}'

        echo -e "\n2. Logs do container (últimas 30 linhas):"
        docker logs "$PORTAINER_CONTAINER_ID" --tail 30 2>&1

        echo -e "\n3. Teste manual de cada endpoint:"
        for endpoint in "${PORTAINER_ENDPOINTS[@]}"; do
            echo "  Testando ${endpoint}:"
            curl -v "${endpoint}/" 2>&1 | head -n 10 | sed 's/^/    /'
            echo ""
        done

        msg_fatal "Não foi possível estabelecer comunicação com o Portainer."
    fi

    # === VERIFICAÇÃO 3: API RESPONDENDO ===
    echo -e "\n${NEGRITO}[Verificação 3/5]${RESET} Verificando se a API do Portainer está respondendo..."
    echo "Usando endpoint: ${PORTAINER_WORKING_ENDPOINT}"

    local api_retries=60
    local api_ready=false
    local api_attempt=0

    while [ $api_retries -gt 0 ]; do
        ((api_attempt++))

        # Testar endpoint /api/users/admin/check
        local check_response
        check_response=$(curl -s --connect-timeout 5 --max-time 10 "${PORTAINER_WORKING_ENDPOINT}/api/users/admin/check" 2>/dev/null)

        # Verificar se recebeu resposta válida
        if [[ "$check_response" == "true" ]] || [[ "$check_response" == "false" ]]; then
            msg_success "API está respondendo!"
            echo "Resposta de /api/users/admin/check: ${check_response}"
            api_ready=true
            break
        fi

        # Aceitar qualquer JSON válido também
        if echo "$check_response" | jq -e . >/dev/null 2>&1; then
            msg_success "API está respondendo com JSON válido!"
            api_ready=true
            break
        fi

        # Debug a cada 10 tentativas
        if [ $((api_attempt % 10)) -eq 0 ]; then
            echo -e "\n  [Debug] Tentativa ${api_attempt}/60"
            echo "  Resposta: '${check_response:0:100}'"
            echo "  Últimas 3 linhas do log:"
            docker logs "$PORTAINER_CONTAINER_ID" --tail 3 2>&1 | sed 's/^/    /'
        elif [ $((api_attempt % 5)) -eq 0 ]; then
            echo -e "\n  Tentativa ${api_attempt}/60 - aguardando API..."
        else
            printf "."
        fi

        sleep 2
        ((api_retries--))
    done
    echo ""

    if [ "$api_ready" = false ]; then
        msg_error "API não respondeu após 120 segundos."
        echo -e "\n${AMARELO}=== DIAGNÓSTICO DA API ===${RESET}"
        echo "1. Teste do endpoint /api/status:"
        curl -v "${PORTAINER_WORKING_ENDPOINT}/api/status" 2>&1 | head -n 20
        echo -e "\n2. Logs completos:"
        docker logs "$PORTAINER_CONTAINER_ID" --tail 50 2>&1
        msg_fatal "API do Portainer não está funcional."
    fi

    # === VERIFICAÇÃO 4: CHECAR SE ADMIN JÁ EXISTE ===
    echo -e "\n${NEGRITO}[Verificação 4/5]${RESET} Verificando se usuário admin já foi criado..."
    local admin_check
    admin_check=$(curl -s --connect-timeout 5 --max-time 10 "${PORTAINER_WORKING_ENDPOINT}/api/users/admin/check" 2>/dev/null || echo "")

    echo "Resposta de /api/users/admin/check: ${admin_check}"

    # Se retornar true, admin já existe
    if [[ "$admin_check" == "true" ]]; then
        msg_warning "Usuário admin já existe no Portainer!"
        echo "Pulando criação da conta."
        local account_created=true
    else
        msg_success "Usuário admin ainda não foi criado. Prosseguindo com criação..."
    fi

    # === VERIFICAÇÃO 5: VERIFICAR SE NÃO ENTROU EM TIMEOUT ===
    echo -e "\n${NEGRITO}[Verificação 5/5]${RESET} Verificando timeout de segurança..."
    local recent_logs
    recent_logs=$(docker logs "$PORTAINER_CONTAINER_ID" --tail 15 --since 300s 2>&1)

    if echo "$recent_logs" | grep -q "timed out for security purposes"; then
        msg_error "Portainer entrou no timeout de 5 minutos!"
        echo "Reiniciando o container..."
        docker restart "$PORTAINER_CONTAINER_ID" >/dev/null 2>&1
        echo "Aguardando 30 segundos..."
        sleep 30

        # Atualizar container ID e endpoint
        PORTAINER_CONTAINER_ID=$(docker ps --filter "name=portainer_portainer" --format "{{.ID}}" | head -n1)
        echo "Novo container ID: ${PORTAINER_CONTAINER_ID}"

        # Re-testar endpoint
        echo "Re-testando endpoint..."
        if test_portainer_endpoint "$PORTAINER_WORKING_ENDPOINT" "/"; then
            msg_success "Portainer reiniciado com sucesso!"
        else
            msg_fatal "Portainer não ficou acessível após reinício."
        fi
    else
        msg_success "Portainer não está em timeout."
    fi

    # === CRIAÇÃO DA CONTA ADMIN ===
    if [ "${account_created:-false}" != "true" ]; then
        echo -e "\n${NEGRITO}Iniciando criação da conta de administrador...${RESET}"
        echo "Usando endpoint: ${PORTAINER_WORKING_ENDPOINT}"
        echo "Tentando criar conta (máximo 20 tentativas)..."

        local max_retries=20
        local account_created=false

        for i in $(seq 1 $max_retries); do
            echo -e "\n${NEGRITO}Tentativa ${i}/${max_retries}${RESET}"

            # Usar endpoint que funcionou
            local init_response
            init_response=$(curl -s -w "\n%{http_code}" \
                --connect-timeout 8 \
                --max-time 15 \
                -X POST "${PORTAINER_WORKING_ENDPOINT}/api/users/admin/init" \
                -H "Content-Type: application/json" \
                --data "{\"Username\": \"admin\", \"Password\": \"${PORTAINER_PASSWORD}\"}" \
                2>&1)

            local http_code=$(echo "$init_response" | tail -n1 | tr -cd '0-9' | tail -c 3)
            local response_body=$(echo "$init_response" | sed '$ d')

            echo "Código HTTP: ${http_code}"

            if [[ "$http_code" == "200" ]]; then
                msg_success "Utilizador 'admin' do Portainer criado com sucesso!"
                echo "Resposta: ${response_body:0:100}"
                account_created=true
                break
            elif [[ "$http_code" == "409" ]]; then
                msg_warning "Utilizador admin já existe (HTTP 409)."
                account_created=true
                break
            elif [[ "$http_code" == "000" ]] || [[ -z "$http_code" ]]; then
                msg_warning "Falha na conexão (HTTP ${http_code:-vazio})."

                # Verificar se container ainda está rodando
                echo "Status do container:"
                docker inspect "$PORTAINER_CONTAINER_ID" --format 'Estado: {{.State.Status}}' 2>/dev/null || echo "Container não encontrado!"

                # Re-testar endpoint
                echo "Re-testando endpoint..."
                if ! test_portainer_endpoint "$PORTAINER_WORKING_ENDPOINT" "/api/users/admin/check"; then
                    msg_warning "Endpoint não está mais respondendo! Tentando encontrar novo endpoint..."

                    # Tentar outros endpoints
                    local new_endpoint_found=false
                    for test_endpoint in "${PORTAINER_ENDPOINTS[@]}"; do
                        if test_portainer_endpoint "$test_endpoint" "/"; then
                            msg_success "Novo endpoint encontrado: ${test_endpoint}"
                            PORTAINER_WORKING_ENDPOINT="$test_endpoint"
                            new_endpoint_found=true
                            break
                        fi
                    done

                    if [ "$new_endpoint_found" = false ]; then
                        msg_error "Nenhum endpoint está respondendo."
                        break
                    fi
                fi
            else
                msg_warning "Falha com código HTTP: ${http_code}"
                echo "Resposta: ${response_body:0:200}"
            fi

            if [ $i -lt $max_retries ]; then
                echo "Aguardando 10 segundos..."
                sleep 10
            fi
        done

        if [ "$account_created" = false ]; then
            msg_error "Não foi possível criar a conta de administrador após ${max_retries} tentativas."
            echo -e "\n${AMARELO}=== DIAGNÓSTICO FINAL ===${RESET}"
            echo "1. Endpoint usado: ${PORTAINER_WORKING_ENDPOINT}"
            echo -e "\n2. Status do container:"
            docker inspect "$PORTAINER_CONTAINER_ID" 2>/dev/null | jq '.[] | {State, NetworkSettings}' || echo "Falha no inspect"
            echo -e "\n3. Logs completos:"
            docker logs "$PORTAINER_CONTAINER_ID" --tail 50 2>&1
            echo -e "\n4. Teste manual do endpoint:"
            curl -v "${PORTAINER_WORKING_ENDPOINT}/api/users/admin/check" 2>&1 | head -n 30
            msg_fatal "Falha na criação da conta do Portainer."
        fi
    fi

    # --- ETAPA 3: OBTENDO CHAVE DE API ---
    msg_header "[3/5] OBTENDO CHAVE DE API DO PORTAINER"

    # Tentar usar domínio HTTPS primeiro (passa pelo Traefik), se falhar usa endpoint que funcionou
    echo "Determinando melhor endpoint para operações da API..."
    local PORTAINER_API_ENDPOINT="https://${PORTAINER_DOMAIN}"

    # Testar se domínio HTTPS está realmente acessível e respondendo com Portainer válido
    echo "Testando se ${PORTAINER_API_ENDPOINT} está acessível..."
    local https_test_response
    https_test_response=$(curl -s -k --connect-timeout 5 --max-time 10 "${PORTAINER_API_ENDPOINT}/api/users/admin/check" 2>/dev/null)

    # Verificar se recebeu resposta válida do Portainer (true, false, ou JSON com "message")
    if [[ "$https_test_response" == "true" ]] || [[ "$https_test_response" == "false" ]] || echo "$https_test_response" | jq -e '.message' >/dev/null 2>&1; then
        msg_success "Domínio HTTPS está acessível via Traefik. Usando: ${PORTAINER_API_ENDPOINT}"
    else
        msg_warning "Domínio HTTPS não está respondendo corretamente ainda."
        echo "Resposta recebida: ${https_test_response:0:100}"
        echo "Usando endpoint direto: ${PORTAINER_WORKING_ENDPOINT}"
        PORTAINER_API_ENDPOINT="$PORTAINER_WORKING_ENDPOINT"
    fi

    # Obter token JWT
    echo "Autenticando para obter token JWT..."
    local jwt_response
    jwt_response=$(curl -s -k --connect-timeout 10 --max-time 20 \
        -X POST "${PORTAINER_API_ENDPOINT}/api/auth" \
        -H "Content-Type: application/json" \
        --data "{\"username\": \"admin\", \"password\": \"${PORTAINER_PASSWORD}\"}")

    local PORTAINER_JWT=$(echo "$jwt_response" | jq -r .jwt)

    if [[ -z "$PORTAINER_JWT" ]] || [[ "$PORTAINER_JWT" == "null" ]]; then
        msg_error "Falha ao obter o token JWT."
        echo "Resposta da API: ${jwt_response}"
        echo "Endpoint usado: ${PORTAINER_API_ENDPOINT}"
        msg_fatal "Não foi possível autenticar no Portainer."
    fi

    msg_success "Token JWT obtido com sucesso."

    # Decodificar token para obter ID do usuário
    echo "Decodificando token para obter ID do utilizador..."
    local USER_ID
    USER_ID=$(echo "$PORTAINER_JWT" | cut -d. -f2 | base64 --decode 2>/dev/null | jq -r .id)

    if [[ -z "$USER_ID" ]] || [[ "$USER_ID" == "null" ]]; then
        msg_error "Falha ao extrair o ID do utilizador do token JWT."
        echo "Token JWT: ${PORTAINER_JWT:0:50}..."
        msg_fatal "Token JWT inválido ou mal formatado."
    fi

    msg_success "ID do utilizador 'admin': ${USER_ID}"

    # Gerar chave de API
    echo "Gerando chave de API..."
    local apikey_response
    apikey_response=$(curl -s -k --connect-timeout 10 --max-time 20 \
        -X POST "${PORTAINER_API_ENDPOINT}/api/users/${USER_ID}/tokens" \
        -H "Authorization: Bearer ${PORTAINER_JWT}" \
        -H "Content-Type: application/json" \
        --data "{\"description\": \"fluxer_installer_key\", \"password\": \"${PORTAINER_PASSWORD}\"}")

    local PORTAINER_API_KEY=$(echo "$apikey_response" | jq -r .rawAPIKey)

    if [[ -z "$PORTAINER_API_KEY" ]] || [[ "$PORTAINER_API_KEY" == "null" ]]; then
        msg_error "Falha ao gerar a chave de API."
        echo "Resposta da API: ${apikey_response}"
        msg_fatal "Não foi possível gerar chave de API."
    fi

    msg_success "Chave de API gerada com sucesso!"

    # Obter Swarm ID
    echo "Obtendo Swarm ID..."
    local ENDPOINT_ID=1
    local SWARM_ID
    SWARM_ID=$(curl -s -k --connect-timeout 10 --max-time 20 \
        -H "X-API-Key: ${PORTAINER_API_KEY}" \
        "${PORTAINER_API_ENDPOINT}/api/endpoints/${ENDPOINT_ID}/docker/swarm" | jq -r .ID)

    if [[ -z "$SWARM_ID" ]] || [[ "$SWARM_ID" == "null" ]]; then
        msg_error "Falha ao obter o Swarm ID."
        echo "Endpoint usado: ${PORTAINER_API_ENDPOINT}"
        echo "Tentando listar endpoints disponíveis:"
        curl -s -k -H "X-API-Key: ${PORTAINER_API_KEY}" "${PORTAINER_API_ENDPOINT}/api/endpoints" | jq '.'
        msg_fatal "Não foi possível obter Swarm ID."
    fi

    msg_success "Swarm ID obtido: ${SWARM_ID}"

    # Salvar endpoint para uso nas próximas etapas
    echo "Endpoint da API para deploy de stacks: ${PORTAINER_API_ENDPOINT}"

    # Extrair apenas o domínio/IP (sem protocolo) para função deploy_stack_via_api
    local PORTAINER_API_HOST
    PORTAINER_API_HOST=$(echo "$PORTAINER_API_ENDPOINT" | sed -e 's|^https\?://||')

    echo "Host da API: ${PORTAINER_API_HOST}"

    # --- ETAPA 4: IMPLANTAR STACKS DE INFRAESTRUTURA E CRIAR DBS ---
    msg_header "[4/5] IMPLANTANDO INFRAESTRUTURA E CRIANDO BANCOS DE DADOS"

    deploy_stack_via_api "redis" "$(generate_redis_yml)" "$PORTAINER_API_KEY" "$PORTAINER_API_HOST" "$SWARM_ID"
    # Re-implanta o stack postgres AQUI, após a remoção explícita do stack e do volume
    deploy_stack_via_api "postgres" "$(generate_postgres_yml)" "$PORTAINER_API_KEY" "$PORTAINER_API_HOST" "$SWARM_ID"
    deploy_stack_via_api "minio" "$(generate_minio_yml)" "$PORTAINER_API_KEY" "$PORTAINER_API_HOST" "$SWARM_ID"
    
    wait_stack "postgres" "postgres"
    wait_stack "minio" "minio"

    create_databases
    echo "Aguardando 15 segundos para o PostgreSQL processar a criação dos bancos de dados..."
    sleep 15 # Adicionado um atraso para dar tempo ao PostgreSQL de se estabilizar

    setup_minio_buckets

    # --- ETAPA 5: IMPLANTAR STACKS DE APLICAÇÃO ---
    msg_header "[5/5] IMPLANTANDO STACKS DE APLICAÇÃO"

    echo "Aguardando 30 segundos antes de implantar as aplicações para garantir a estabilidade da infraestrutura..."
    sleep 30 # Aumenta o atraso antes de implantar as aplicações

    # Estratégia: Implantar apenas o n8n_editor para rodar as migrations primeiro
    msg_header "IMPLANTANDO N8N EDITOR PARA MIGRATIONS"
    deploy_stack_via_api "n8n-migrations" "$(generate_n8n_editor_only_yml)" "$PORTAINER_API_KEY" "$PORTAINER_API_HOST" "$SWARM_ID"
    wait_stack "n8n-migrations" "n8n_editor" # Espera o editor estar online
    echo "N8n editor online. Aguardando 90 segundos para as migrations completarem..."
    sleep 90 # Tempo para as migrations rodarem

    msg_header "REMOVENDO N8N EDITOR TEMPORÁRIO E IMPLANTANDO STACK COMPLETO DO N8N"
    docker stack rm n8n-migrations >/dev/null 2>&1
    sleep 10 # Aguarda a remoção do stack temporário

    # Agora, e somente agora, subimos os stacks de aplicação completos
    deploy_stack_via_api "n8n" "$(generate_n8n_yml)" "$PORTAINER_API_KEY" "$PORTAINER_API_HOST" "$SWARM_ID"
    deploy_stack_via_api "typebot" "$(generate_typebot_yml)" "$PORTAINER_API_KEY" "$PORTAINER_API_HOST" "$SWARM_ID"
    deploy_stack_via_api "evolution" "$(generate_evolution_yml)" "$PORTAINER_API_KEY" "$PORTAINER_API_HOST" "$SWARM_ID"


    # --- RESUMO FINAL ---
    msg_header "🎉 INSTALAÇÃO CONCLUÍDA 🎉"
    echo "Aguarde alguns minutos para que todos os serviços sejam iniciados."; echo "Pode verificar o estado no seu painel Portainer ou com o comando: ${NEGRITO}docker service ls${RESET}"; echo; echo "Abaixo estão os seus links de acesso:"; echo
    echo -e "${NEGRITO}Painel Portainer:      https://${PORTAINER_DOMAIN}${RESET}"
    echo -e "${NEGRITO}Painel n8n (editor):   https://${N8N_EDITOR_DOMAIN}${RESET}"
    echo -e "${NEGRITO}Builder Typebot:       https://${TYPEBOT_EDITOR_DOMAIN}${RESET}"
    echo -e "${NEGRITO}MinIO Painel:          https://${MINIO_CONSOLE_DOMAIN}${RESET}"
    echo -e "${NEGRITO}Evolution API:         https://${EVOLUTION_DOMAIN}${RESET}"
    echo
    read -p "Deseja exibir as senhas e chaves geradas? (s/N): " SHOW_CREDS < /dev/tty
    if [[ "$SHOW_CREDS" =~ ^[Ss]$ ]]; then
        echo; msg_header "CREDENCIAS GERADAS (guarde em local seguro)"
        echo -e "${NEGRITO}Senha do Portainer:      ${PORTAINER_PASSWORD}${RESET}"
        echo -e "${NEGRITO}Utilizador root do MinIO: ${MINIO_ROOT_USER}${RESET}"
        echo -e "${NEGRITO}Senha root do MinIO:     ${MINIO_ROOT_PASSWORD}${RESET}"
        echo -e "${NEGRITO}Chave da Evolution API: ${EVOLUTION_API_KEY}${RESET}"
        echo -e "${NEGRITO}Senha do Postgres:       ${POSTGRES_PASSWORD}${RESET}"
    fi
    echo; msg_success "Tudo pronto! Aproveite o seu novo ambiente de automação."

    # Limpar cache após instalação bem-sucedida
    clear_cache
}

# --- PONTO DE ENTRADA DO SCRIPT ---
main "$@"
