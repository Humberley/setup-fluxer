#!/bin/bash

#-------------------------------------------------------------------------------
# Script: Instalador de Ambiente Fluxer - VERSÃO CORRIGIDA
# Descrição: Corrige problemas com API do Portainer e adiciona fallback
# Autor: Humberley / Corrigido
# Versão: 12.1 (Correção API + Fallback)
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

# Função para testar conectividade da API do Portainer
test_portainer_api() {
    local portainer_domain=$1
    local api_key=$2
    
    echo "Testando conectividade da API do Portainer..."
    local response
    response=$(curl -s -k -w "\n%{http_code}" -H "X-API-Key: ${api_key}" \
        "https://${portainer_domain}/api/endpoints")
    
    local http_code
    http_code=$(tail -n1 <<< "$response")
    
    if [[ "$http_code" == "200" ]]; then
        msg_success "API do Portainer está funcionando!"
        return 0
    else
        msg_error "API do Portainer não está respondendo corretamente (Código: ${http_code})"
        return 1
    fi
}

# Função CORRIGIDA para implantar stack via API do Portainer
deploy_stack_via_api() {
    local stack_name=$1
    local compose_content=$2
    local api_key=$3
    local portainer_domain=$4
    local swarm_id=$5
    local endpoint_id=1

    echo "-----------------------------------------------------"
    echo "Implantando o stack: ${NEGRITO}${stack_name}${RESET}..."

    # Criar payload JSON corrigido
    local json_payload
    json_payload=$(jq -n \
        --arg name "$stack_name" \
        --arg content "$compose_content" \
        --arg swarmID "$swarm_id" \
        '{
            Name: $name,
            StackFileContent: $content,
            SwarmID: $swarmID,
            Env: []
        }')

    # Tentar múltiplos endpoints da API
    local endpoints=(
        "https://${portainer_domain}/api/stacks?type=1&method=string&endpointId=${endpoint_id}"
        "https://${portainer_domain}/api/stacks/create/swarm/string?endpointId=${endpoint_id}"
        "https://${portainer_domain}/api/stacks?endpointId=${endpoint_id}&type=1&method=string"
    )

    for endpoint in "${endpoints[@]}"; do
        echo "Tentando endpoint: ${endpoint}"
        
        local response
        response=$(curl -s -k -w "\n%{http_code}" -X POST \
            -H "X-API-Key: ${api_key}" \
            -H "Content-Type: application/json" \
            --data-binary "$json_payload" \
            "$endpoint")
        
        local http_code
        http_code=$(tail -n1 <<< "$response")
        local response_body
        response_body=$(sed '$ d' <<< "$response")

        if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
            msg_success "Stack '${stack_name}' implantado com sucesso via API!"
            return 0
        else
            echo "Falha no endpoint (Código: ${http_code})"
            echo "Resposta: ${response_body}"
        fi
    done

    # Se chegou aqui, todos os endpoints falharam
    msg_error "Falha ao implantar '${stack_name}' via API em todos os endpoints testados."
    
    # FALLBACK: Usar docker stack deploy diretamente
    msg_warning "Tentando fallback com docker stack deploy..."
    
    if echo "$compose_content" | docker stack deploy --compose-file - "$stack_name"; then
        msg_success "Stack '${stack_name}' implantado com sucesso via docker stack deploy!"
        return 0
    else
        msg_error "Falha também no fallback para '${stack_name}'"
        return 1
    fi
}

# Função para verificar versão do Portainer
check_portainer_version() {
    local portainer_domain=$1
    local api_key=$2
    
    echo "Verificando versão do Portainer..."
    local response
    response=$(curl -s -k -H "X-API-Key: ${api_key}" \
        "https://${portainer_domain}/api/status")
    
    local version
    version=$(echo "$response" | jq -r '.Version // "unknown"')
    
    if [[ "$version" != "unknown" && "$version" != "null" ]]; then
        msg_success "Versão do Portainer: ${version}"
        
        # Verificar se é uma versão que suporta a API de stacks
        if [[ "$version" =~ ^2\.[0-9]+\.[0-9]+$ ]]; then
            msg_success "Versão compatível com API de stacks."
            return 0
        else
            msg_warning "Versão do Portainer pode não ser totalmente compatível."
            return 1
        fi
    else
        msg_error "Não foi possível determinar a versão do Portainer."
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
      - DATABASE_ENABLED=true
      - DATABASE_PROVIDER=postgresql
      - DATABASE_CONNECTION_URI=postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/evolution
      - CACHE_REDIS_ENABLED=true
      - CACHE_REDIS_URI=redis://redis:6379
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
    echo -e "${VERDE}${NEGRITO}🛠 INSTALADOR FLUXER - VERSÃO CORRIGIDA${RESET}"

    # --- COLETA DE DADOS DO USUÁRIO COM VALIDAÇÃO ---
    msg_header "COLETANDO INFORMAÇÕES"
    while true; do read -p "🌐 Qual é o seu domínio principal (ex: seudominio.com.br): " DOMINIO_RAIZ < /dev/tty; if validate_domain "$DOMINIO_RAIZ"; then break; fi; done
    while true; do read -p "📧 Email para o certificado SSL (Let's Encrypt): " LE_EMAIL < /dev/tty; if validate_email "$LE_EMAIL"; then break; fi; done
    while true; do echo -e "${AMARELO}--> A senha deve ter no mínimo 12 caracteres, com maiúsculas, minúsculas, números e especiais.${RESET}"; read -s -p "🔑 Digite uma senha para o Portainer: " PORTAINER_PASSWORD < /dev/tty; echo; if validate_password "$PORTAINER_PASSWORD"; then read -s -p "🔑 Confirme a senha do Portainer: " PORTAINER_PASSWORD_CONFIRM < /dev/tty; echo; if [[ "$PORTAINER_PASSWORD" == "$PORTAINER_PASSWORD_CONFIRM" ]]; then break; else msg_warning "As senhas não coincidem."; fi; fi; done
    while true; do read -p "👤 Utilizador root para o MinIO (sem espaços ou especiais): " MINIO_ROOT_USER < /dev/tty; if validate_simple_text "$MINIO_ROOT_USER"; then break; fi; done
    while true; do echo -e "${AMARELO}--> A senha deve ter no mínimo 8 caracteres.${RESET}"; read -s -p "🔑 Digite uma senha para o MinIO: " MINIO_ROOT_PASSWORD < /dev/tty; echo; if [ ${#MINIO_ROOT_PASSWORD} -ge 8 ]; then read -s -p "🔑 Confirme a senha do MinIO: " MINIO_ROOT_PASSWORD_CONFIRM < /dev/tty; echo; if [[ "$MINIO_ROOT_PASSWORD" == "$MINIO_ROOT_PASSWORD_CONFIRM" ]]; then break; else msg_warning "As senhas não coincidem."; fi; else msg_warning "A senha do MinIO precisa ter no mínimo 8 caracteres."; fi; done

    # --- GERAÇÃO DE VARIÁVEIS E VERIFICAÇÃO DE DNS ---
    msg_header "GERANDO CONFIGURAÇÕES E VERIFICANDO DNS"
    export DOMINIO_RAIZ LE_EMAIL PORTAINER_PASSWORD MINIO_ROOT_USER MINIO_ROOT
