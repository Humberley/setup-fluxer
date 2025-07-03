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
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.portainer.rule=Host(\`${PORTAINER_DOMAIN}\`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"
        - "traefik.docker.network=${REDE_DOCKER}"

volumes:
  evolution_instances:
    external: true
    name: evolution_instances
networks:
  ${REDE_DOCKER}:
    external: true
    name: ${REDE_DOCKER}
EOL
    docker stack deploy --compose-file /tmp/portainer.yml portainer || msg_fatal "Falha ao implantar Portainer."
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
