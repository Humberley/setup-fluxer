#!/bin/bash

#-------------------------------------------------------------------------------
# Script: Instalador de Ambiente Fluxer
# Descrição: Implementa a lógica de instalação robusta do SetupOrion,
#            incluindo preparação, deploy, verificação e configuração em etapas.
# Autor: Humberley / [Seu Nome]
# Versão: 10.2 (Corrige a geração de YAML)
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
    msg_header "Aguardando o serviço ${stack_name} ficar online"
    while true; do
        if docker service ls --filter "name=${stack_name}" | grep -q "1/1"; then
            msg_success "Serviço ${stack_name} está online."
            break
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

    # --- COLETA DE DADOS DO USUÁRIO COM VALIDAÇÃO ---
    msg_header "COLETANDO INFORMAÇÕES"
    while true; do read -p "🌐 Qual é o seu domínio principal (ex: seudominio.com.br): " DOMINIO_RAIZ < /dev/tty; if validate_domain "$DOMINIO_RAIZ"; then break; fi; done
    while true; do read -p "📧 Email para o certificado SSL (Let's Encrypt): " LE_EMAIL < /dev/tty; if validate_email "$LE_EMAIL"; then break; fi; done
    while true; do echo -e "${AMARELO}--> A senha deve ter no mínimo 12 caracteres, com maiúsculas, minúsculas, números e especiais.${RESET}"; read -s -p "🔑 Digite uma senha para o Portainer: " PORTAINER_PASSWORD < /dev/tty; echo; if validate_password "$PORTAINER_PASSWORD"; then read -s -p "🔑 Confirme a senha do Portainer: " PORTAINER_PASSWORD_CONFIRM < /dev/tty; echo; if [[ "$PORTAINER_PASSWORD" == "$PORTAINER_PASSWORD_CONFIRM" ]]; then break; else msg_warning "As senhas não coincidem."; fi; fi; done
    
    # --- GERAÇÃO DE VARIÁVEIS E VERIFICAÇÃO DE DNS ---
    msg_header "GERANDO CONFIGURAÇÕES E VERIFICANDO DNS"
    export DOMINIO_RAIZ LE_EMAIL PORTAINER_PASSWORD
    export PORTAINER_DOMAIN="portainer.${DOMINIO_RAIZ}"
    export REDE_DOCKER="fluxerNet"
    msg_success "Variáveis geradas."

    check_dns "${PORTAINER_DOMAIN}"

    # --- PREPARAÇÃO DO AMBIENTE SWARM ---
    msg_header "PREPARANDO O AMBIENTE SWARM"
    echo "Garantindo a existência da rede Docker overlay '${REDE_DOCKER}'..."; docker network rm "$REDE_DOCKER" >/dev/null 2>&1; docker network create --driver=overlay --attachable "$REDE_DOCKER" || msg_fatal "Falha ao criar a rede overlay '${REDE_DOCKER}'."; msg_success "Rede '${REDE_DOCKER}' pronta."
    echo "Criando os volumes Docker..."; docker volume create "portainer_data" >/dev/null; docker volume create "volume_swarm_certificates" >/dev/null; docker volume create "volume_swarm_shared" >/dev/null; msg_success "Volumes prontos."

    # --- ETAPA 1: INSTALAR TRAEFIK E PORTAINER ---
    msg_header "[1/3] INSTALANDO TRAEFIK E PORTAINER"
    
    # --- Deploy Traefik ---
    echo "---"; echo "Implantando: ${NEGRITO}traefik${RESET}..."
    cat > /tmp/traefik.yml << EOL
version: "3.7"
services:
  traefik:
    image: traefik:v2.11
    command:
      - "--api.dashboard=true"
      - "--providers.docker.swarmMode=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--certificatesresolvers.letsencryptresolver.acme.email=${LE_EMAIL}"
      - "--certificatesresolvers.letsencryptresolver.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
      - "--log.level=ERROR"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "volume_swarm_certificates:/letsencrypt"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
    networks:
      - ${REDE_DOCKER}
    deploy:
      placement:
        constraints:
          - node.role == manager

networks:
  ${REDE_DOCKER}:
    external: true
    name: ${REDE_DOCKER}

volumes:
  volume_swarm_certificates:
    external: true
    name: volume_swarm_certificates
EOL
    docker stack deploy --compose-file /tmp/traefik.yml traefik || msg_fatal "Falha ao implantar Traefik."
    msg_success "Stack 'traefik' implantado."
    rm /tmp/traefik.yml

    # --- Deploy Portainer ---
    echo "---"; echo "Implantando: ${NEGRITO}portainer${RESET}..."
    cat > /tmp/portainer.yml << EOL
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
      - portainer_data:/data
    networks:
      - ${REDE_DOCKER}
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
  portainer_data:
    external: true
    name: portainer_data

networks:
  ${REDE_DOCKER}:
    external: true
    name: ${REDE_DOCKER}
EOL
    docker stack deploy --compose-file /tmp/portainer.yml portainer || msg_fatal "Falha ao implantar Portainer."
    msg_success "Stack 'portainer' implantado."
    rm /tmp/portainer.yml

    # --- ETAPA 2: VERIFICAR SERVIÇOS E CONFIGURAR PORTAINER ---
    msg_header "[2/3] VERIFICANDO SERVIÇOS E CONFIGURANDO PORTAINER"
    wait_stack "traefik_traefik"
    wait_stack "portainer_portainer"
    
    echo "Aguardando 30 segundos para estabilização dos serviços antes de criar a conta..."
    sleep 30

    echo "Tentando criar conta de administrador no Portainer..."
    local max_retries=10
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
            echo "Tentativa ${i}/${max_retries} falhou. A aguardar 15 segundos..."
            sleep 15
        fi
    done

    if [ "$account_created" = false ]; then
        msg_fatal "Não foi possível criar a conta de administrador no Portainer. Verifique os logs do Traefik e Portainer e as configurações de firewall."
    fi

    # --- ETAPA 3: ARMAZENAR CREDENCIAIS E FINALIZAR ---
    msg_header "[3/3] GERANDO TOKEN E ARMAZENANDO CREDENCIAIS"
    
    echo "A autenticar para obter token JWT..."
    local jwt_response
    jwt_response=$(curl -s -k -X POST "https://${PORTAINER_DOMAIN}/api/auth" \
        -H "Content-Type: application/json" \
        --data "{\"username\": \"admin\", \"password\": \"${PORTAINER_PASSWORD}\"}")
    local PORTAINER_JWT=$(echo "$jwt_response" | jq -r .jwt)
    if [[ -z "$PORTAINER_JWT" || "$PORTAINER_JWT" == "null" ]]; then msg_fatal "Falha ao obter o token JWT."; fi
    msg_success "Token JWT obtido."

    local DADOS_DIR="/root/dados_vps"
    mkdir -p "$DADOS_DIR"
    local DADOS_FILE="${DADOS_DIR}/dados_portainer"
    echo "Salvando credenciais do Portainer em ${DADOS_FILE}..."
    {
        echo "[ PORTAINER ]"
        echo "Dominio do portainer: https://${PORTAINER_DOMAIN}"
        echo "Usuario: admin"
        echo "Senha: ${PORTAINER_PASSWORD}"
        echo "Token: ${PORTAINER_JWT}"
    } > "$DADOS_FILE"
    chmod 600 "$DADOS_FILE"
    msg_success "Credenciais salvas com sucesso."

    msg_header "🎉 INSTALAÇÃO DA BASE CONCLUÍDA 🎉"
    echo "O ambiente base com Traefik e Portainer está pronto."
    echo "Agora você pode executar outros scripts para instalar aplicações adicionais."
    echo
    echo -e "${NEGRITO}Acesse o seu Portainer em: https://${PORTAINER_DOMAIN}${RESET}"
    echo -e "Use o utilizador 'admin' e a senha que você definiu."
    echo
}

# --- PONTO DE ENTRADA DO SCRIPT ---
main
