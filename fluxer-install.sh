#!/bin/bash

#-------------------------------------------------------------------------------
# Script: Instalador de Ambiente Fluxer (Corrigido v5)
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
      - N8N_REINSTALL_MISSING_PACKAGES=true
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      - N8N_NODE_PATH=/home/node/.n8n/nodes
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true

      - N8N_SMTP_SENDER=${SMTP_USER}
      - N8N_SMTP_USER=${SMTP_USER}
      - N8N_SMTP_PASS=${SMTP_PASS}
      - N8N_SMTP_HOST=${SMTP_HOST}
      - N8N_SMTP_PORT=${SMTP_PORT}
      - N8N_SMTP_SSL=${SMTP_SSL}

      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=2
      - NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash # 'moment-with-locales' removido
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=336

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
      - N8N_REINSTALL_MISSING_PACKAGES=true
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      - N8N_NODE_PATH=/home/node/.n8n/nodes
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true

      - N8N_SMTP_SENDER=${SMTP_USER}
      - N8N_SMTP_USER=${SMTP_USER}
      - N8N_SMTP_PASS=${SMTP_PASS}
      - N8N_SMTP_HOST=${SMTP_HOST}
      - N8N_SMTP_PORT=${SMTP_PORT}
      - N8N_SMTP_SSL=${SMTP_SSL}

      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=2
      - NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash # 'moment-with-locales' removido
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=336

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
      - N8N_REINSTALL_MISSING_PACKAGES=true
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      - N8N_NODE_PATH=/home/node/.n8n/nodes
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true

      - N8N_SMTP_SENDER=${SMTP_USER}
      - N8N_SMTP_USER=${SMTP_USER}
      - N8N_SMTP_PASS=${SMTP_PASS}
      - N8N_SMTP_HOST=${SMTP_HOST}
      - N8N_SMTP_PORT=${SMTP_PORT}
      - N8N_SMTP_SSL=${SMTP_SSL}

      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=2
      - NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash # 'moment-with-locales' removido
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=336

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


# === FUNÇÃO PRINCIPAL ===
main() {
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


    # --- COLETA DE DADOS DO USUÁRIO COM VALIDAÇÃO ---
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
    

    # --- GERAÇÃO DE VARIÁVEIS E VERIFICAÇÃO DE DNS ---
    msg_header "GERANDO CONFIGURAÇÕES E VERIFICANDO DNS"
    export DOMINIO_RAIZ LE_EMAIL PORTAINER_PASSWORD MINIO_ROOT_USER MINIO_ROOT_PASSWORD SMTP_USER SMTP_PASS
    export SMTP_HOST="smtp.gmail.com"
    export SMTP_PORT="587"
    export SMTP_SSL="true"
    
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
    
    export POSTGRES_VOLUME="postgres_data"
    export REDIS_VOLUME="redis_data"
    export MINIO_VOLUME="minio_data"
    export EVOLUTION_VOLUME="evolution_instances"
    
    msg_success "Variáveis geradas."

    check_dns "${PORTAINER_DOMAIN}"

    # --- PREPARAÇÃO DO AMBIENTE SWARM ---
    msg_header "PREPARANDO O AMBIENTE SWARM"
    echo "Garantindo a existência da rede Docker overlay '${REDE_DOCKER}'..."; docker network rm "$REDE_DOCKER" >/dev/null 2>&1; docker network create --driver=overlay --attachable "$REDE_DOCKER" || msg_fatal "Falha ao criar a rede overlay '${REDE_DOCKER}'."; msg_success "Rede '${REDE_DOCKER}' pronta."
    echo "Criando os volumes Docker...";
    
    # Remover o stack do Postgres e o volume para garantir um ambiente limpo
    echo "Removendo stacks antigos do n8n (se existirem)..."
    docker stack rm n8n >/dev/null 2>&1
    sleep 10 # Aguarda a remoção do stack do n8n
    
    echo "Removendo stack 'postgres' e volume '${POSTGRES_VOLUME}' para garantir ambiente limpo...";
    docker stack rm postgres >/dev/null 2>&1 # Remover o stack postgres
    sleep 10 # Aumenta a pausa para o swarm processar a remoção do stack
    docker volume rm "${POSTGRES_VOLUME}" >/dev/null 2>&1
    sleep 5 # Aumenta a pausa para o sistema de arquivos liberar o volume

    docker volume create "portainer_data" >/dev/null
    docker volume create "volume_swarm_certificates" >/dev/null
    docker volume create "volume_swarm_shared" >/dev/null
    docker volume create "${POSTGRES_VOLUME}" >/dev/null # Recria o volume
    docker volume create "${REDIS_VOLUME}" >/dev/null
    docker volume create "${MINIO_VOLUME}" >/dev/null
    docker volume create "${EVOLUTION_VOLUME}" >/dev/null
    msg_success "Volumes prontos."

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
    
    echo "Aguardando 30 segundos para estabilização dos serviços..."; sleep 30

    echo "Tentando criar conta de administrador no Portainer..."; local max_retries=10; local account_created=false
    for i in $(seq 1 $max_retries); do
        local init_response; init_response=$(curl -s -k -w "\n%{http_code}" -X POST "https://${PORTAINER_DOMAIN}/api/users/admin/init" -H "Content-Type: application/json" --data "{\"Username\": \"admin\", \"Password\": \"${PORTAINER_PASSWORD}\"}"); local http_code=$(tail -n1 <<< "$init_response"); local response_body=$(sed '$ d' <<< "$init_response")
        if [[ "$http_code" == "200" ]]; then msg_success "Utilizador 'admin' do Portainer criado!"; account_created=true; break; else msg_warning "Tentativa ${i}/${max_retries} falhou."; echo "Código HTTP: ${http_code}"; echo "Resposta: ${response_body}"; echo "Aguardando 15s..."; sleep 15; fi
    done
    if [ "$account_created" = false ]; then msg_fatal "Não foi possível criar a conta de administrador no Portainer."; fi

    # --- ETAPA 3: OBTENDO CHAVE DE API ---
    msg_header "[3/5] OBTENDO CHAVE DE API DO PORTAINER"
    echo "A autenticar para obter token JWT..."; local jwt_response; jwt_response=$(curl -s -k -X POST "https://${PORTAINER_DOMAIN}/api/auth" -H "Content-Type: application/json" --data "{\"username\": \"admin\", \"password\": \"${PORTAINER_PASSWORD}\"}"); local PORTAINER_JWT=$(echo "$jwt_response" | jq -r .jwt); if [[ -z "$PORTAINER_JWT" || "$PORTAINER_JWT" == "null" ]]; then msg_fatal "Falha ao obter o token JWT."; fi; msg_success "Token JWT obtido."
    
    echo "Decodificando token para obter o ID do utilizador..."; local USER_ID; USER_ID=$(echo "$PORTAINER_JWT" | cut -d. -f2 | base64 --decode 2>/dev/null | jq -r .id); if [[ -z "$USER_ID" || "$USER_ID" == "null" ]]; then msg_fatal "Falha ao extrair o ID do utilizador do token JWT."; fi; msg_success "ID do utilizador 'admin' é: ${USER_ID}"

    echo "A gerar chave de API..."; local apikey_response; apikey_response=$(curl -s -k -X POST "https://${PORTAINER_DOMAIN}/api/users/${USER_ID}/tokens" -H "Authorization: Bearer ${PORTAINER_JWT}" -H "Content-Type: application/json" --data "{\"description\": \"fluxer_installer_key\", \"password\": \"${PORTAINER_PASSWORD}\"}"); local PORTAINER_API_KEY=$(echo "$apikey_response" | jq -r .rawAPIKey); if [[ -z "$PORTAINER_API_KEY" || "$PORTAINER_API_KEY" == "null" ]]; then msg_error "A resposta da API para criação da chave foi: $apikey_response"; msg_fatal "Falha ao gerar a chave de API."; fi; msg_success "Chave de API gerada!"

    echo "Obtendo Swarm ID..."; local ENDPOINT_ID=1; local SWARM_ID; SWARM_ID=$(curl -s -k -H "X-API-Key: ${PORTAINER_API_KEY}" "https://${PORTAINER_DOMAIN}/api/endpoints/${ENDPOINT_ID}/docker/swarm" | jq -r .ID); if [[ -z "$SWARM_ID" || "$SWARM_ID" == "null" ]]; then msg_fatal "Falha ao obter o Swarm ID."; fi; msg_success "Swarm ID obtido: ${SWARM_ID}"

    # --- ETAPA 4: IMPLANTAR STACKS DE INFRAESTRUTURA E CRIAR DBS ---
    msg_header "[4/5] IMPLANTANDO INFRAESTRUTURA E CRIANDO BANCOS DE DADOS"
    
    deploy_stack_via_api "redis" "$(generate_redis_yml)" "$PORTAINER_API_KEY" "$PORTAINER_DOMAIN" "$SWARM_ID"
    # Re-implanta o stack postgres AQUI, após a remoção explícita do stack e do volume
    deploy_stack_via_api "postgres" "$(generate_postgres_yml)" "$PORTAINER_API_KEY" "$PORTAINER_DOMAIN" "$SWARM_ID"
    deploy_stack_via_api "minio" "$(generate_minio_yml)" "$PORTAINER_API_KEY" "$PORTAINER_DOMAIN" "$SWARM_ID"
    
    wait_stack "postgres" "postgres"
    wait_stack "minio" "minio"

    create_databases
    echo "Aguardando 15 segundos para o PostgreSQL processar a criação dos bancos de dados..."
    sleep 15 # Adicionado um atraso para dar tempo ao PostgreSQL de se estabilizar

    # --- ETAPA 5: IMPLANTAR STACKS DE APLICAÇÃO ---
    msg_header "[5/5] IMPLANTANDO STACKS DE APLICAÇÃO"

    echo "Aguardando 30 segundos antes de implantar as aplicações para garantir a estabilidade da infraestrutura..."
    sleep 30 # Aumenta o atraso antes de implantar as aplicações

    # Agora, e somente agora, subimos o stack do n8n
    deploy_stack_via_api "n8n" "$(generate_n8n_yml)" "$PORTAINER_API_KEY" "$PORTAINER_DOMAIN" "$SWARM_ID"
    
    deploy_stack_via_api "typebot" "$(generate_typebot_yml)" "$PORTAINER_API_KEY" "$PORTAINER_DOMAIN" "$SWARM_ID"
    deploy_stack_via_api "evolution" "$(generate_evolution_yml)" "$PORTAINER_API_KEY" "$PORTAINER_DOMAIN" "$SWARM_ID"


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
}

# --- PONTO DE ENTRADA DO SCRIPT ---
main
