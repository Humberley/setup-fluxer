#!/bin/bash

#-------------------------------------------------------------------------------
# Script: Instalador de Ambiente Fluxer
# Descrição: Coleta as informações do usuário, prepara o ambiente Docker Swarm
#            e inicia os serviços, com foco na robustez da inicialização do Portainer.
# Autor: Humberley / [Seu Nome]
# Versão: 5.0 (Diagnóstico melhorado para inicialização do Portainer)
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
    echo -e "\n${VERMELHO}❌ ERRO: $1${RESET}"
    # Não sai mais do script, permite diagnóstico
}
msg_fatal() {
    echo -e "\n${VERMELHO}❌ ERRO FATAL: $1${RESET}\n"
    exit 1
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
        apt-get update -qq && apt-get install -y gettext-base -qq || msg_fatal "Falha ao instalar 'gettext-base'."
    fi
    if ! command -v jq &> /dev/null; then
        msg_warning "Comando 'jq' não encontrado. A instalar..."
        apt-get update -qq && apt-get install -y jq -qq || msg_fatal "Falha ao instalar 'jq'."
    fi
    msg_success "Dependências prontas."

    # --- VERIFICAÇÃO DO DOCKER SWARM ---
    msg_header "VERIFICANDO AMBIENTE DOCKER SWARM"
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        msg_warning "Docker Swarm não está ativo. A inicializar..."
        if ! docker swarm init; then
            msg_fatal "Falha ao inicializar o Docker Swarm."
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

    # --- GERAÇÃO DE VARIÁVEIS E SUBDOMÍNIOS ---
    msg_header "GERANDO CONFIGURAÇÕES"
    echo "Gerando subdomínios e chaves de segurança..."

    export DOMINIO_RAIZ LE_EMAIL PORTAINER_PASSWORD

    export PORTAINER_DOMAIN="portainer.${DOMINIO_RAIZ}"
    export N8N_EDITOR_DOMAIN="n8n.${DOMINIO_RAIZ}"
    export N8N_WEBHOOK_DOMAIN="nwn.${DOMINIO_RAIZ}"
    # ... outros domínios ...

    export POSTGRES_PASSWORD=$(openssl rand -hex 16)
    export N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
    
    export PORTAINER_VOLUME="portainer_data"
    export POSTGRES_VOLUME="postgres_data"
    export REDIS_VOLUME="redis_data"
    export REDE_DOCKER="fluxerNet"
    
    msg_success "Configurações geradas e exportadas para o ambiente."

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
    docker volume create "volume_swarm_certificates" >/dev/null
    docker volume create "volume_swarm_shared" >/dev/null
    msg_success "Volumes prontos."

    # --- INICIANDO OS STACKS BASE ---
    msg_header "INICIANDO STACKS BASE (TRAEFIK E PORTAINER)"
    
    local STACKS_DIR="stacks"
    
    # ETAPA 1: Implantar Traefik e Portainer via CLI
    for stack_name in "traefik" "portainer"; do
        local template_file="${STACKS_DIR}/${stack_name}/${stack_name}.template.yml"
        if [ ! -f "$template_file" ]; then msg_warning "Ficheiro para '${stack_name}' não encontrado. A saltar."; continue; fi
        
        echo "-----------------------------------------------------"
        echo "Implantando o stack base: ${NEGRITO}${stack_name}${RESET}..."
        
        # Substitui as variáveis no template antes de implantar
        local processed_file="/tmp/${stack_name}.yml"
        envsubst < "$template_file" > "$processed_file"

        if docker stack deploy --compose-file "$processed_file" "$stack_name"; then
            msg_success "Stack '${stack_name}' implantado com sucesso!"
        else
            msg_fatal "Houve um problema ao implantar o stack '${stack_name}'. Verifique o ficheiro /tmp/${stack_name}.yml"
        fi
        rm "$processed_file"
    done

    # ETAPA 2: Configurar Portainer e obter chave de API
    msg_header "CONFIGURANDO PORTAINER E OBTENDO CHAVE DE API"

    echo "A aguardar que o Portainer fique online em https://${PORTAINER_DOMAIN}..."
    echo "Isto pode demorar alguns minutos enquanto o certificado SSL é gerado pelo Traefik."

    local wait_time=0
    local max_wait=300 # 5 minutos de espera máxima

    while ! curl -s -k --fail "https://${PORTAINER_DOMAIN}/api/health" > /dev/null; do
        wait_time=$((wait_time + 15))
        if [ $wait_time -ge $max_wait ]; then
            msg_error "O Portainer não ficou online após ${max_wait} segundos."
            echo "--- DIAGNÓSTICO ---"
            echo -e "${AMARELO}Verificando estado dos serviços...${RESET}"
            docker service ls
            echo -e "\n${AMARELO}--- Logs do Traefik (últimos 30 segundos) ---${RESET}"
            docker service logs --tail 50 --since 30s traefik_traefik
            echo -e "\n${AMARELO}--- Logs do Portainer (últimos 30 segundos) ---${RESET}"
            docker service logs --tail 50 --since 30s portainer_portainer
            msg_fatal "A instalação não pode continuar. Verifique os logs acima para encontrar a causa do problema."
        fi
        printf "."
        sleep 15
    done
    echo
    msg_success "Portainer está online!"

    echo "A criar utilizador 'admin' do Portainer..."
    local init_response
    init_response=$(curl -s -k -w "%{http_code}" -X POST "https://${PORTAINER_DOMAIN}/api/users/admin/init" \
        -H "Content-Type: application/json" \
        --data "{\"Password\": \"${PORTAINER_PASSWORD}\"}")
    
    local http_code=${init_response: -3}
    if [[ "$http_code" != "200" ]]; then
        msg_error "Falha ao criar o utilizador admin do Portainer (Código: $http_code)."
        msg_fatal "Resposta da API: ${init_response::-3}"
    fi
    msg_success "Utilizador 'admin' criado."

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

    # ETAPA 3: Armazenar credenciais
    msg_header "ARMAZENANDO CREDENCIAIS"
    local DADOS_DIR="/root/dados_vps"
    mkdir -p "$DADOS_DIR"
    local DADOS_FILE="${DADOS_DIR}/dados_portainer"
    echo "Salvando credenciais do Portainer em ${DADOS_FILE}..."
    {
        echo "URL: https://${PORTAINER_DOMAIN}"
        echo "Username: admin"
        echo "Password: ${PORTAINER_PASSWORD}"
        echo "API Key: ${PORTAINER_API_KEY}"
    } > "$DADOS_FILE"
    chmod 600 "$DADOS_FILE"
    msg_success "Credenciais salvas com sucesso."
    
    # ETAPA 4: Implantar o resto dos stacks via API do Portainer
    msg_header "IMPLANTANDO STACKS DE APLICAÇÃO VIA API DO PORTAINER"
    # ... (O resto do script para implantar n8n, typebot, etc. continua aqui) ...
    # Esta parte permanece a mesma do script original.

    # --- RESUMO FINAL ---
    msg_header "🎉 INSTALAÇÃO CONCLUÍDA 🎉"
    # ... (O resumo final permanece o mesmo) ...
}

# --- PONTO DE ENTRADA DO SCRIPT ---
main
