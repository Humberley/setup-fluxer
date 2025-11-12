#!/bin/bash

#-------------------------------------------------------------------------------
# Script: Correção Rápida de Labels do Traefik
# Descrição: Re-aplica labels do Traefik aos serviços existentes
# Uso: bash fix-traefik-labels.sh
#-------------------------------------------------------------------------------

# Cores
VERDE='\033[1;32m'
AZUL='\033[1;34m'
AMARELO='\033[1;33m'
VERMELHO='\033[1;31m'
RESET='\033[0m'

msg_success() {
    echo -e "${VERDE}✔ $1${RESET}"
}
msg_warning() {
    echo -e "${AMARELO}⚠️ $1${RESET}"
}
msg_error() {
    echo -e "${VERMELHO}❌ ERRO: $1${RESET}"
}

echo -e "${AZUL}========================================${RESET}"
echo -e "${AZUL}Correção de Labels do Traefik${RESET}"
echo -e "${AZUL}========================================${RESET}"
echo ""

# Verificar se está no diretório correto
if [ ! -f "/opt/setup-fluxer/fluxer-install.sh" ]; then
    msg_error "Script deve ser executado no diretório /opt/setup-fluxer"
    exit 1
fi

cd /opt/setup-fluxer || exit 1

# Carregar variáveis e funções do instalador
echo "Carregando configurações..."
source /root/.fluxer-install-cache 2>/dev/null || {
    msg_error "Cache de configuração não encontrado. Execute o instalador primeiro."
    exit 1
}

# Carregar funções de geração de YAML
source fluxer-install.sh

msg_success "Configurações carregadas."

echo ""
echo -e "${AMARELO}Este script irá re-fazer o deploy de:${RESET}"
echo "  - Traefik"
echo "  - Portainer"
echo "  - n8n"
echo "  - Typebot"
echo "  - Evolution"
echo "  - MinIO"
echo ""
echo "Os serviços serão atualizados sem perda de dados."
echo "Isso levará aproximadamente 2-3 minutos."
echo ""
read -p "Deseja continuar? (s/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "Operação cancelada."
    exit 0
fi

echo ""
echo "Iniciando correção..."
echo ""

# 1. Traefik
echo "1/6 - Re-deploy do Traefik..."
generate_traefik_yml > /tmp/traefik_fixed.yml
docker stack deploy --prune --resolve-image always -c /tmp/traefik_fixed.yml traefik >/dev/null 2>&1
if [ $? -eq 0 ]; then
    msg_success "Traefik atualizado"
else
    msg_error "Falha ao atualizar Traefik"
fi
rm -f /tmp/traefik_fixed.yml

# 2. Portainer
echo "2/6 - Re-deploy do Portainer..."
generate_portainer_yml > /tmp/portainer_fixed.yml
docker stack deploy --prune --resolve-image always -c /tmp/portainer_fixed.yml portainer >/dev/null 2>&1
if [ $? -eq 0 ]; then
    msg_success "Portainer atualizado"
else
    msg_error "Falha ao atualizar Portainer"
fi
rm -f /tmp/portainer_fixed.yml

# 3. MinIO
echo "3/6 - Re-deploy do MinIO..."
generate_minio_yml > /tmp/minio_fixed.yml
docker stack deploy --prune --resolve-image always -c /tmp/minio_fixed.yml minio >/dev/null 2>&1
if [ $? -eq 0 ]; then
    msg_success "MinIO atualizado"
else
    msg_error "Falha ao atualizar MinIO"
fi
rm -f /tmp/minio_fixed.yml

# 4. n8n
echo "4/6 - Re-deploy do n8n..."
generate_n8n_yml > /tmp/n8n_fixed.yml
docker stack deploy --prune --resolve-image always -c /tmp/n8n_fixed.yml n8n >/dev/null 2>&1
if [ $? -eq 0 ]; then
    msg_success "n8n atualizado"
else
    msg_error "Falha ao atualizar n8n"
fi
rm -f /tmp/n8n_fixed.yml

# 5. Typebot
echo "5/6 - Re-deploy do Typebot..."
generate_typebot_yml > /tmp/typebot_fixed.yml
docker stack deploy --prune --resolve-image always -c /tmp/typebot_fixed.yml typebot >/dev/null 2>&1
if [ $? -eq 0 ]; then
    msg_success "Typebot atualizado"
else
    msg_error "Falha ao atualizar Typebot"
fi
rm -f /tmp/typebot_fixed.yml

# 6. Evolution
echo "6/6 - Re-deploy do Evolution..."
generate_evolution_yml > /tmp/evolution_fixed.yml
docker stack deploy --prune --resolve-image always -c /tmp/evolution_fixed.yml evolution >/dev/null 2>&1
if [ $? -eq 0 ]; then
    msg_success "Evolution atualizado"
else
    msg_error "Falha ao atualizar Evolution"
fi
rm -f /tmp/evolution_fixed.yml

echo ""
echo "Aguardando 30 segundos para serviços estabilizarem..."
sleep 30

echo ""
echo -e "${AZUL}========================================${RESET}"
echo -e "${AZUL}Verificando Labels${RESET}"
echo -e "${AZUL}========================================${RESET}"
echo ""

# Verificar labels do Portainer
echo "Labels do Portainer:"
docker service inspect portainer_portainer --format '{{json .Spec.TaskTemplate.ContainerSpec.Labels}}' 2>/dev/null | jq '.' || msg_warning "Não foi possível verificar labels"

echo ""
echo "Verificando se Traefik reconheceu as rotas..."
sleep 10

# Tentar acessar Portainer
echo "Testando acesso ao Portainer..."
response=$(curl -s -o /dev/null -w "%{http_code}" -k https://${PORTAINER_DOMAIN}/ 2>/dev/null || echo "000")
if [[ "$response" =~ ^[23] ]]; then
    msg_success "Portainer acessível via HTTPS (HTTP $response)"
else
    msg_warning "Portainer retornou HTTP $response - Aguarde mais alguns minutos"
fi

echo ""
echo -e "${VERDE}========================================${RESET}"
echo -e "${VERDE}Correção Concluída!${RESET}"
echo -e "${VERDE}========================================${RESET}"
echo ""
echo "Aguarde 2-3 minutos para o Traefik gerar os certificados SSL."
echo ""
echo "Acesse: https://${PORTAINER_DOMAIN}"
echo ""
echo "Se ainda aparecer 404, verifique os logs:"
echo "  docker service logs traefik_traefik --tail 50"
echo ""
