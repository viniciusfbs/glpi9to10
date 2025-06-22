#!/bin/bash

set -e  # Encerra o script em caso de erro

# ====================================================================
# CONTINUAÇÃO DA MIGRAÇÃO GLPI 9.4.4 → 10.0.18
# ====================================================================
# ETAPAS JÁ REALIZADAS (comentadas):
# ✅ Containers MariaDB e GLPI 9.4.4 já estão rodando
# ✅ Backup já foi restaurado no banco
# ✅ GLPI 9.4.4 já está instalado e funcionando
# ✅ Correções do banco já foram aplicadas
# ✅ Todas as variáveis e diretórios já estão configurados
# ====================================================================

# ==================== VARIÁVEIS GLOBAIS REUTILIZADAS ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Reutilizando variáveis da instalação anterior
NOME="${1:-vini1}"
C_GLPI_10="glpi10_${NOME}"
C_MARIADB="mariadb-${NOME}"
GLPI10_IMAGE="glpi10_${NOME}_imagem"
GLPI_DATA_DIR="/var/glpi-${NOME}-dir"

# ==================== FUNÇÕES DE LOG ====================
log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

wait_for_container() {
    local container=$1
    local max_attempts=30
    local attempt=0

    log_info "Aguardando container $container estar pronto..."

    while [ $attempt -lt $max_attempts ]; do
        if docker ps | grep -q $container; then
            log_success "Container $container está rodando"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    log_error "Timeout esperando container $container"
    return 1
}

# iniciando atualizacao do GLPI 10
log_info "🚀 Iniciando continuação da migração para GLPI 10.0.18"


# ==================== FUNÇÃO DE LIMPEZA ====================
cleanup_existing_glpi10() {
    log_info "🧹 Verificando se container GLPI 10 já existe..."

    # Verificar se container existe (rodando ou parado)
    if docker ps -a --format "table {{.Names}}" | grep -q "^${C_GLPI_10}$"; then
        log_warning "Container $C_GLPI_10 já existe. Removendo..."

        # Parar container se estiver rodando
        if docker ps --format "table {{.Names}}" | grep -q "^${C_GLPI_10}$"; then
            log_info "Parando container $C_GLPI_10..."
            docker stop $C_GLPI_10 || {
                log_error "Falha ao parar container $C_GLPI_10"
                exit 1
            }
        fi

        # Remover container
        log_info "Removendo container $C_GLPI_10..."
        docker rm $C_GLPI_10 || {
            log_error "Falha ao remover container $C_GLPI_10"
            exit 1
        }

        log_success "Container $C_GLPI_10 removido com sucesso"
    else
        log_info "Container $C_GLPI_10 não existe. Continuando..."
    fi

    # Verificar se imagem já existe
    if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^${GLPI10_IMAGE}:latest$"; then
        log_warning "Imagem $GLPI10_IMAGE já existe. Removendo..."
        docker rmi $GLPI10_IMAGE || {
            log_warning "Não foi possível remover imagem $GLPI10_IMAGE (pode estar em uso)"
        }
    fi
}

# ==================== CONTINUAÇÃO DA MIGRAÇÃO ====================
migrate_to_glpi_10() {
    log_info "🚀 CONTINUANDO: Migração para GLPI 10.0.18"

    # NOVO: Limpeza preventiva
    cleanup_existing_glpi10

    # 1. Buildar imagem GLPI 10
    log_info "🐳 Construindo imagem Docker GLPI 10: $GLPI10_IMAGE"
    docker build -t "$GLPI10_IMAGE" "${SCRIPT_DIR}/GLPI9.Xto10/glpi10/" || {
        log_error "Falha ao construir imagem Docker GLPI 10"
        exit 1
    }
    log_success "Imagem GLPI 10 construída com sucesso"

    # 2. Iniciar container GLPI 10
    log_info "🚀 Iniciando container GLPI 10: $C_GLPI_10"
    docker run --name $C_GLPI_10 \
        --link $C_MARIADB:mariadb \
        -v ${GLPI_DATA_DIR}:/var/www/html/glpi \
        -p 2611:80 \
        -d $GLPI10_IMAGE

    wait_for_container $C_GLPI_10
    sleep 5  # Aguardar Apache

    # 3. Baixar GLPI 10.0.18
    log_info "📥 Baixando GLPI 10.0.18"
    docker exec $C_GLPI_10 bash -c "cd /var/www/html/ && wget -q https://github.com/glpi-project/glpi/releases/download/10.0.18/glpi-10.0.18.tgz"

    # 4. Extrair GLPI 10
    log_info "📦 Extraindo GLPI 10.0.18"
    docker exec $C_GLPI_10 bash -c "cd /var/www/html/ && tar -zxf glpi-10.0.18.tgz"

    # 5. Configurar permissões
    log_info "🔐 Configurando permissões"
    docker exec $C_GLPI_10 chown -R www-data:www-data /var/www/html/glpi/

    # 6. Configurar conexão com banco (reutilizando configuração existente)
    log_info "⚙️  Configurando conexão com banco"
    docker exec $C_GLPI_10 bash -c "cat > /var/www/html/glpi/config/config_db.php << 'EOF'
<?php
class DB extends DBmysql {
   public \$dbhost = 'mariadb';
   public \$dbuser = 'root';
   public \$dbpassword = 'glpi';
   public \$dbdefault = 'glpi';
   public \$use_utf8mb4 = true;
   public \$allow_myisam = false;
   public \$allow_datetime = false;
   public \$allow_signed_keys = false;
}
EOF"

    docker exec "$C_GLPI" bash -c "
            chown -R www-data:www-data /var/www/html/glpi &&
            chmod -R 755 /var/www/html/glpi &&
            chmod -R 755 /var/www/html/glpi/files &&
            chmod -R 755 /var/www/html/glpi/config
        "
    sleep 5

    docker exec "$C_GLPI" bash -c "
            chown -R www-data:www-data /var/www/html/glpi &&
            chmod -R 755 /var/www/html/glpi &&
            chmod -R 755 /var/www/html/glpi/files &&
            chmod -R 755 /var/www/html/glpi/config
        "

    # 7. Executar upgrade para GLPI 10
    log_info "🔄 Continue via tela a atualizaçaõ do GLPI 10..."
    return 0
}

# ==================== EXECUÇÃO ====================

log_info "🚀 Iniciando continuação da migração para GLPI 10"
log_info "📋 Instância: $NOME"

# Verificar se Docker está rodando
if ! docker ps >/dev/null 2>&1; then
    log_error "Docker não está rodando!"
    exit 1
fi

# Executar migração
if migrate_to_glpi_10; then
    echo ""
    echo "========================================"
    echo "🎉 MIGRAÇÃO PARA GLPI 10 CONCLUÍDA!"
    echo "========================================"
    echo -e "${BLUE}🌐 GLPI 10 URL: http://localhost:2611/glpi${NC}"
    echo -e "${BLUE}👤 Usuário: glpi${NC}"
    echo -e "${BLUE}🔐 Senha: glpi${NC}"
    echo ""
    echo -e "${GREEN}✅ Container GLPI 10: $C_GLPI_10${NC}"
    echo -e "${GREEN}✅ Usando banco: $C_MARIADB${NC}"
    echo "========================================"

    log_success "🚀 Migração concluída com sucesso!"
else
    log_error "❌ Falha na migração"
    log_info "Para debug: docker exec -it $C_GLPI_10 bash"
    exit 1
fi
