#!/bin/bash

#-------------------------------------------------------------------------------
# Script: Instalador Mestre Fluxer
# Descrição: Prepara uma VPS Ubuntu nova, instalando TODAS as dependências
#            necessárias para o ecossistema Fluxer.
# Autor: Humberley / [Seu Nome]
# Versão: 4.0 (Com preparação de sistema robusta)
#-------------------------------------------------------------------------------

# === VARIÁVEIS GLOBAIS ===
VERDE='\033[1;32m'
AZUL='\033[1;34m'
AMARELO='\033[1;33m'
VERMELHO='\033[1;31m'
NEGRITO='\033[1m'
RESET='\033[0m'

INSTALL_DIR="/opt/setup-fluxer"
REPO_URL="https://github.com/Humberley/setup-fluxer.git"
INSTALL_SCRIPT_NAME="fluxer-install.sh"

# === FUNÇÕES AUXILIARES ===
msg_header() {
    echo -e "\n${AZUL}${NEGRITO}#-----------------------------------------------------#"
    echo -e "# ${1}"
    echo -e "#-----------------------------------------------------#${RESET}"
}
msg_success() {
    echo -e "${VERDE}✔ $1${RESET}"
}
msg_warning() {
    echo -e "${AMARELO}⚠️ $1${RESET}"
}
msg_error() {
    echo -e "\n${VERMELHO}❌ ERRO: $1${RESET}\n"
    exit 1
}
command_exists() {
    command -v "$1" &> /dev/null
}

# === FUNÇÕES DE INSTALAÇÃO ===

# 1. Prepara o sistema com TODAS as dependências necessárias
prepare_system() {
    msg_header "Preparando o Sistema (Ubuntu)"

    if [ "$(id -u)" -ne 0 ]; then
        msg_error "Este script precisa ser executado como root. Use: curl ... | sudo bash"
    fi
    msg_success "Executando com permissões de root."

    echo "Atualizando a lista de pacotes..."
    if ! apt-get update -qq; then
        msg_error "Falha ao atualizar a lista de pacotes (apt-get update)."
    fi
    
    echo "Instalando atualizações do sistema..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq; then
        msg_warning "Ocorreu um problema durante o 'apt-get upgrade'."
    fi

    # Lista de pacotes essenciais para todo o ecossistema
    local essential_packages="curl git jq apt-utils dialog apache2-utils gettext-base dnsutils"
    
    echo "Verificando e instalando dependências essenciais..."
    for pkg in $essential_packages; do
        if ! command_exists "$pkg"; then
            echo "Instalando ${pkg}..."
            if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" -qq; then
                msg_error "Falha ao instalar o pacote essencial '${pkg}'."
            fi
        else
            echo "${pkg} já está instalado."
        fi
    done

    msg_success "Sistema preparado e todas as dependências instaladas."
}

# 2. Instala o Docker Engine
install_docker() {
    msg_header "Instalando o Docker Engine"
    if command_exists docker; then
        msg_success "Docker já está instalado."
        return
    fi

    msg_warning "Docker não encontrado. Instalando agora..."
    if ! curl -fsSL https://get.docker.com -o get-docker.sh; then
        msg_error "Falha ao baixar o script de instalação do Docker."
    fi
    
    if ! sh get-docker.sh; then
        msg_error "O script de instalação do Docker falhou."
    fi
    
    rm get-docker.sh
    msg_success "Docker Engine instalado com sucesso."
}

# 3. Instala o Docker Compose
install_docker_compose() {
    msg_header "Instalando o Docker Compose"
    if command_exists docker-compose; then
        msg_success "Docker Compose já está instalado."
        return
    fi
    
    msg_warning "Docker Compose não encontrado. Instalando agora..."
    
    local LATEST_COMPOSE_VERSION
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    if [ -z "$LATEST_COMPOSE_VERSION" ]; then
        msg_error "Não foi possível obter a última versão do Docker Compose da API do GitHub."
    fi
    
    local DESTINATION="/usr/local/bin/docker-compose"
    
    if ! curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o "${DESTINATION}"; then
        msg_error "Falha ao baixar o binário do Docker Compose."
    fi
    
    if ! chmod +x "${DESTINATION}"; then
        msg_error "Falha ao tornar o Docker Compose executável."
    fi
    
    msg_success "Docker Compose ${LATEST_COMPOSE_VERSION} instalado com sucesso."
}

# 4. Clona ou atualiza o repositório de configuração
setup_repository() {
    msg_header "Configurando o Repositório de Instalação"
    
    if [ -d "$INSTALL_DIR" ]; then
        msg_warning "Diretório ${INSTALL_DIR} já existe. Atualizando..."
        cd "$INSTALL_DIR" || msg_error "Não foi possível acessar o diretório ${INSTALL_DIR}"
        
        git reset --hard HEAD >/dev/null 2>&1
        
        if ! git pull; then
            msg_error "Falha ao atualizar o repositório com 'git pull'."
        fi
        msg_success "Repositório atualizado."
    else
        echo "Clonando repositório de ${REPO_URL}..."
        if ! git clone "${REPO_URL}" "${INSTALL_DIR}"; then
            msg_error "Falha ao clonar o repositório."
        fi
        msg_success "Repositório clonado com sucesso para ${INSTALL_DIR}."
    fi
}

# === FUNÇÃO PRINCIPAL (MAIN) ===
main() {
    clear
    echo -e "${AZUL}${NEGRITO}🚀 Iniciando o Instalador Mestre Fluxer v4.0...${RESET}"
    
    prepare_system
    install_docker
    install_docker_compose
    setup_repository
    
    cd "$INSTALL_DIR" || msg_error "Diretório de instalação ${INSTALL_DIR} não encontrado."
    
    if [ ! -f "$INSTALL_SCRIPT_NAME" ]; then
        msg_error "O script de instalação '${INSTALL_SCRIPT_NAME}' não foi encontrado no repositório."
    fi
    
    msg_header "Entregando para o Instalador do Ambiente Fluxer"
    echo "O ambiente está pronto. O script principal será executado agora."
    sleep 3
    
    chmod +x "$INSTALL_SCRIPT_NAME"
    ./"$INSTALL_SCRIPT_NAME"
}

# --- PONTO DE ENTRADA DO SCRIPT ---
main
