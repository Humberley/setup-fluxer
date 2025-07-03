#!/bin/bash

#-------------------------------------------------------------------------------
# Script: Instalador Mestre Fluxer
# Descrição: Prepara uma VPS Ubuntu nova, espelhando o processo robusto do
#            SetupOrion para garantir que todas as dependências e configurações
#            de sistema estejam prontas antes de prosseguir.
# Autor: Humberley / [Seu Nome]
# Versão: 5.0 (Final - Lógica Orion implementada)
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

    echo -e "\n${NEGRITO}1/14 - [ OK ] - Fazendo Update...${RESET}"
    apt-get update -qq || msg_warning "Falha no apt-get update."

    echo -e "${NEGRITO}2/14 - [ OK ] - Fazendo Upgrade...${RESET}"
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq || msg_warning "Falha no apt-get upgrade."
    
    local packages_to_install="sudo apt-utils dialog jq apache2-utils git python3 gettext-base dnsutils"
    local step=3
    for pkg in $packages_to_install; do
        echo -e "${NEGRITO}${step}/14 - [ OK ] - Verificando/Instalando ${pkg}...${RESET}"
        apt-get install -y "$pkg" -qq
        step=$((step + 1))
    done

    echo -e "${NEGRITO}11/14 - [ OK ] - Configurando Timezone...${RESET}"
    timedatectl set-timezone America/Sao_Paulo

    local server_name="fluxer-vps"
    echo -e "${NEGRITO}12/14 - [ OK ] - Configurando Hostname para '${server_name}'...${RESET}"
    hostnamectl set-hostname "$server_name"
    sed -i "s/127.0.0.1[[:space:]]localhost/127.0.0.1 ${server_name}/g" /etc/hosts > /dev/null 2>&1

    echo -e "${NEGRITO}13/14 - [ OK ] - Fazendo Update final...${RESET}"
    apt-get update -qq
    
    echo -e "${NEGRITO}14/14 - [ OK ] - Instalando AppArmor...${RESET}"
    apt-get install -y apparmor-utils -qq

    msg_success "Sistema preparado e todas as dependências instaladas."
}

# 2. Instala o Docker e inicializa o Swarm
install_docker_swarm() {
    msg_header "Instalando Docker e Iniciando Swarm"

    if ! command_exists docker; then
        echo "Instalando Docker..."
        curl -fsSL https://get.docker.com | bash > /dev/null 2>&1 || msg_error "Falha ao instalar o Docker."
        systemctl enable docker > /dev/null 2>&1
        systemctl start docker > /dev/null 2>&1
        msg_success "Docker instalado."
    else
        msg_success "Docker já está instalado."
    fi

    if docker info 2>/dev/null | grep -q "Swarm: active"; then
        msg_success "Docker Swarm já está ativo."
        return
    fi

    echo "Iniciando Docker Swarm..."
    local public_ip
    public_ip=$(curl -s ifconfig.me)
    if [ -z "$public_ip" ]; then
        msg_error "Não foi possível obter o IP público da VPS."
    fi

    local max_attempts=3
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if docker swarm init --advertise-addr "$public_ip" > /dev/null 2>&1; then
            msg_success "Docker Swarm iniciado com sucesso!"
            return
        else
            msg_warning "Tentativa ${attempt} de ${max_attempts} para iniciar o Swarm falhou. A aguardar 5 segundos..."
            attempt=$((attempt + 1))
            sleep 5
        fi
    done
    
    msg_error "Não foi possível iniciar o Docker Swarm após ${max_attempts} tentativas. Verifique a configuração de rede."
}

# 3. Clona ou atualiza o repositório de configuração
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
    echo -e "${AZUL}${NEGRITO}🚀 Iniciando o Instalador Mestre Fluxer v5.0...${RESET}"
    
    prepare_system
    install_docker_swarm
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