#!/bin/bash

#-------------------------------------------------------------------------------
# Script: Inicializador Fluxer
# Descrição: Prepara o ambiente da VPS instalando Docker, Docker Compose
#            e, em seguida, executa o script de instalação principal.
# Autor: Seu Nome/Empresa
# Versão: 1.1
#-------------------------------------------------------------------------------

# === VARIÁVEIS DE CORES E ESTILOS ===
VERDE='\033[1;32m'
AZUL='\033[1;34m'
AMARELO='\033[1;33m'
VERMELHO='\033[1;31m'
NEGRITO='\033[1m'
RESET='\033[0m'

# === FUNÇÕES AUXILIARES PARA EXIBIR MENSAGENS ===
msg_info() {
    echo -e "\n${AZUL}${NEGRITO}# $1${RESET}"
}

msg_success() {
    echo -e "${VERDE}✔ $1${RESET}"
}

msg_warning() {
    echo -e "${AMARELO}⚠️ $1${RESET}"
}

msg_error() {
    echo -e "${VERMELHO}❌ ERRO: $1${RESET}"
    exit 1
}

# --- PONTO DE ENTRADA DO SCRIPT ---
main() {
    clear
    echo -e "${AZUL}🚀 Iniciando o inicializador Fluxer...${RESET}"

    # 1. VERIFICA SE O SCRIPT ESTÁ SENDO EXECUTADO COMO ROOT
    msg_info "Verificando permissões de superusuário..."
    if [ "$(id -u)" -ne 0 ]; then
        msg_error "Este script precisa ser executado como root. Use 'sudo ./seu_script.sh'"
    fi
    msg_success "Executando como root."

    # 2. INSTALA O DOCKER
    msg_info "Verificando instalação do Docker..."
    if ! command -v docker &> /dev/null; then
        msg_warning "Docker não encontrado. Instalando agora..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        if sh get-docker.sh; then
            msg_success "Docker instalado com sucesso."
            rm get-docker.sh
        else
            msg_error "Falha ao instalar o Docker."
        fi
    else
        msg_success "Docker já está instalado."
    fi

    # 3. INSTALA O DOCKER COMPOSE
    msg_info "Verificando instalação do Docker Compose..."
    if ! command -v docker-compose &> /dev/null; then
        msg_warning "Docker Compose não encontrado. Instalando agora..."
        # Encontra a última versão do Docker Compose e instala
        LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
        if [ -z "$LATEST_COMPOSE_VERSION" ]; then
            msg_error "Não foi possível obter a última versão do Docker Compose. Verifique sua conexão."
        fi
        
        DESTINATION="/usr/local/bin/docker-compose"
        curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o "${DESTINATION}"
        
        if [ $? -eq 0 ]; then
            chmod +x "${DESTINATION}"
            msg_success "Docker Compose ${LATEST_COMPOSE_VERSION} instalado com sucesso."
        else
            msg_error "Falha ao baixar o Docker Compose."
        fi
    else
        msg_success "Docker Compose já está instalado."
    fi

    # 4. CLONA OU ATUALIZA O REPOSITÓRIO DE CONFIGURAÇÃO
    INSTALL_DIR="/opt/setup-fluxer"
    msg_info "Configurando o repositório em ${INSTALL_DIR}..."

    if [ -d "$INSTALL_DIR" ]; then
        msg_warning "Diretório ${INSTALL_DIR} já existe. Atualizando..."
        cd "$INSTALL_DIR" || msg_error "Não foi possível acessar o diretório ${INSTALL_DIR}"
        if git pull; then
            msg_success "Repositório atualizado."
        else
            msg_error "Falha ao atualizar o repositório."
        fi
    else
        msg_info "Clonando repositório de instalação..."
        if git clone https://github.com/Humberley/setup-fluxer.git "$INSTALL_DIR"; then
            msg_success "Repositório clonado com sucesso."
        else
            msg_error "Falha ao clonar o repositório."
        fi
    fi

    # 5. EXECUTA O INSTALADOR PRINCIPAL
    cd "$INSTALL_DIR" || msg_error "Não foi possível acessar o diretório ${INSTALL_DIR}"
    
    if [ ! -f "fluxer-install.sh" ]; then
        msg_error "O script 'fluxer-install.sh' não foi encontrado no repositório."
    fi
    
    msg_info "Tornando o instalador principal executável..."
    chmod +x fluxer-install.sh
    
    echo
    echo -e "${VERDE}-------------------------------------------------------------------"
    echo -e "✅ Ambiente preparado. Iniciando o instalador principal agora..."
    echo -e "-------------------------------------------------------------------${RESET}"
    echo
    
    # Executa o script que está no Canvas
    ./fluxer-install.sh
}

# Chama a função principal
main
