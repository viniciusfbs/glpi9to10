#!/bin/bash

set -e  # Encerra o script em caso de erro

# Cores para output com timestamp
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Função para log colorido com timestamp
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

# Função para mostrar uso
usage() {
    echo "==================================="
    echo "🚀 Script de Migração GLPI 9.4.4"
    echo "==================================="
    echo "Uso: $0 [nome_instancia]"
    echo ""
    echo "Exemplos:"
    echo "  $0 vini1"
    echo "  $0 producao"
    echo ""
    echo "Se nenhum nome for fornecido, será usado 'vini1' como padrão"
    echo ""
    echo "Opções:"
    echo "  -h, --help    Mostra esta ajuda"
    echo ""
    echo "Arquivos de backup suportados (deve estar no diretório atual):"
    echo "  - glpi25.sql"
    echo "  - glpi_full.sql"
}

# Função para aguardar container estar pronto
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

# Função para aguardar MySQL estar pronto
wait_for_mysql() {
    local container=$1
    local max_attempts=30
    local attempt=0
    
    log_info "Aguardando MySQL estar pronto..."
    
    while [ $attempt -lt $max_attempts ]; do
        if docker exec $container mysql -uroot -pglpi -e "SELECT 1;" >/dev/null 2>&1; then
            log_success "MySQL está pronto e acessível"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 3
    done
    
    log_error "Timeout esperando MySQL ficar acessível"
    return 1
}

# Função para aguardar Apache estar pronto
wait_for_apache() {
    
    log_info "Aguardando Apache estar pronto..."
    sleep 5
    return 0
}

# Função para executar comandos SQL com tratamento de erro
execute_sql() {
    local container=$1
    local sql=$2
    local description="${3:-SQL Command}"
    
    log_info "Executando: $description"
    if docker exec $container mysql -uroot -pglpi glpi -e "$sql" 2>/dev/null; then
        log_success "$description - OK"
    else
        log_warning "$description - Falhou, mas continuando..."
    fi
}

# Função para executar comandos de correção do banco
fix_database_issues() {
    local container=$1
    
    log_info "Aplicando correções no banco de dados..."
    
    # Correção 1: glpi_tickettemplatemandatoryfields
    execute_sql $container \
        "DELETE t1 FROM glpi_tickettemplatemandatoryfields t1 INNER JOIN glpi_tickettemplatemandatoryfields t2 ON t1.tickettemplates_id = t2.tickettemplates_id AND t1.num = t2.num WHERE t1.id > t2.id;" \
        "Removendo duplicatas de tickettemplatemandatoryfields"
    
    execute_sql $container \
        "ALTER TABLE glpi_tickettemplatemandatoryfields ADD UNIQUE unicity (tickettemplates_id, num);" \
        "Adicionando índice único em tickettemplatemandatoryfields"
    
    # Correção 2: glpi_logs
    execute_sql $container \
        "ALTER TABLE glpi_logs ADD INDEX id_search_option(id_search_option);" \
        "Adicionando índice em glpi_logs"
    
    # Correção 3: glpi_slalevels_tickets
    execute_sql $container \
        "DELETE t1 FROM glpi_slalevels_tickets t1 INNER JOIN glpi_slalevels_tickets t2 WHERE t1.id > t2.id AND t1.tickets_id = t2.tickets_id AND t1.slalevels_id = t2.slalevels_id;" \
        "Removendo duplicatas de slalevels_tickets"
    
    execute_sql $container \
        "ALTER TABLE glpi_slalevels_tickets ADD UNIQUE unicity (tickets_id, slalevels_id);" \
        "Adicionando índice único em slalevels_tickets"
    
    log_success "Correções aplicadas no banco de dados"
}

# Função para detectar arquivo de backup
detect_backup_file() {
    if [ -f "./glpi25.sql" ]; then
        echo "glpi25.sql"
        return 0
    elif [ -f "./glpi_full.sql" ]; then
        echo "glpi_full.sql"
        return 0
    else
        return 1
    fi
}

# Função para executar update do GLPI com retry
attempt_update_with_fixes() {
    local c_glpi=$1
    local c_mariadb=$2
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Tentativa $attempt de $max_attempts para atualizar o GLPI..."
        
        if docker exec $c_glpi php /var/www/html/glpi/bin/console glpi:database:update --no-interaction --force; then
            log_success "Update do GLPI concluído com sucesso!"
            return 0
        else
            log_warning "Update falhou na tentativa $attempt"
            if [ $attempt -lt $max_attempts ]; then
                log_info "Reaplicando correções no banco de dados..."
                fix_database_issues $c_mariadb
                sleep 5
            fi
        fi
        
        ((attempt++))
    done
    
    log_error "Update falhou após $max_attempts tentativas"
    return 1
}

# Função principal de instalação
install_glpi() {
    local NOME="${1:-vini1}"
    
    # Verificação de arquivos de backup
    local backup_file
    if ! backup_file=$(detect_backup_file); then
        log_error "Nenhum arquivo de backup encontrado!"
        log_info "Arquivos suportados: glpi25.sql ou glpi_full.sql"
        log_info "Coloque um desses arquivos no diretório atual do script."
        exit 1
    fi
    
    log_success "Arquivo de backup encontrado: $backup_file"
    
    # Definições de variáveis
    local BASE_DIR="/var/${NOME}"
    local C_GLPI="glpi_${NOME}"
    local C_MARIADB="mariadb-${NOME}"
    
    log_info "🚀 Iniciando migração do GLPI para instância: $NOME"
    
    # Limpeza de containers anteriores
    log_info "🧹 Removendo containers anteriores se existirem..."
    docker stop $C_GLPI $C_MARIADB 2>/dev/null || true
    docker rm $C_GLPI $C_MARIADB 2>/dev/null || true
    
    # Criação dos diretórios
    log_info "📁 Criando diretório base: $BASE_DIR"
    mkdir -p "$BASE_DIR"
    cd "$BASE_DIR"
    
    # Build da imagem Docker
    log_info "🐳 Construindo imagem Docker glpi_${NOME}_imagem"
    cd /root/
    docker build -t "glpi_${NOME}_imagem" "${SCRIPT_DIR}/GLPI9.Xto10" || {
        log_error "Falha ao construir imagem Docker"
        exit 1
    }
    
    # Diretórios de dados com permissões corretas
    log_info "📂 Criando diretório MySQL: /var/lib/mysql-${NOME}"
    sudo mkdir -p "/var/lib/mysql-${NOME}"
    sudo chown 999:999 "/var/lib/mysql-${NOME}"
    
    log_info "📂 Criando diretório GLPI: /var/glpi-${NOME}-dir"
    sudo mkdir -p "/var/glpi-${NOME}-dir"
    sudo chown 999:999 "/var/glpi-${NOME}-dir"
    
    # Subir container MariaDB
    log_info "🗄️  Iniciando container MariaDB"
    docker run --name $C_MARIADB \
        -v /var/lib/mysql-${NOME}:/var/lib/mysql \
        -e MYSQL_ROOT_PASSWORD=glpi \
        -e MYSQL_DATABASE=glpi \
        -p 3306:3306 \
        -d mariadb:10.4
    
    wait_for_container $C_MARIADB
    wait_for_mysql $C_MARIADB
    
    # Subir container GLPI
    log_info "🌐 Iniciando container GLPI"
    docker run --name $C_GLPI \
        --link $C_MARIADB:mariadb \
        -v /var/glpi-${NOME}-dir:/var/www/html/glpi \
        -p 2610:80 \
        -d glpi_${NOME}_imagem
    
    wait_for_container $C_GLPI
    wait_for_apache $C_GLPI
    
    # Restaurar backup do banco
    log_info "💾 Restaurando backup do banco de dados ($backup_file)"
    log_info "💾 Copiando backup para o container"
    docker cp "${SCRIPT_DIR}/${backup_file}" "$C_MARIADB:/tmp/" || {
        log_error "Falha ao copiar o arquivo para o container"
        exit 1
    }
    log_info "💾 Restaurando backup dentro do container"
    docker exec -i $C_MARIADB bash -c "mariadb -u root -pglpi glpi < /tmp/${backup_file}" || {
        log_error "Falha ao restaurar o backup"
        exit 1
    }
    log_success "Backup restaurado com sucesso"

    # Instalar GLPI
    log_info "📥 Baixando GLPI 9.4.4"
    docker exec $C_GLPI bash -c "cd /var/www/html/ && wget -q https://github.com/glpi-project/glpi/releases/download/9.4.4/glpi-9.4.4.tgz"
    
    log_info "📦 Extraindo GLPI"
    docker exec $C_GLPI bash -c "cd /var/www/html/ && tar -zxf glpi-9.4.4.tgz"
    
    log_info "🔐 Configurando permissões"
    docker exec $C_GLPI chown -R www-data:www-data /var/www/html/glpi/
    docker exec $C_GLPI chmod -R 755 /var/www/html/glpi/files
    docker exec $C_GLPI chmod -R 755 /var/www/html/glpi/config
    
    # Criar arquivo de configuração do banco
    log_info "⚙️  Criando arquivo de configuração do banco"
    docker exec $C_GLPI bash -c "cat > /var/www/html/glpi/config/config_db.php << 'EOF'
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
    
    # Aplicar correções preventivas no banco
    fix_database_issues $C_MARIADB
    
    # Executar update com tentativas automáticas
    if attempt_update_with_fixes $C_GLPI $C_MARIADB; then
        # Limpeza de cache
        log_info "🧹 Limpando cache do GLPI"
        docker exec $C_GLPI rm -rf /var/www/html/glpi/files/_cache/* 2>/dev/null || true
        
        # Ajustar permissões finais
        log_info "🔐 Ajustando permissões finais"
        docker exec $C_GLPI chown -R www-data:www-data /var/www/html/glpi/
        
        log_success "🎉 Migração do GLPI concluída com sucesso!"
        echo ""
        echo "========================================"
        echo "📋 INFORMAÇÕES DE ACESSO:"
        echo "========================================"
        echo -e "${BLUE}🌐 URL: http://localhost/glpi${NC}"
        echo -e "${BLUE}👤 Usuário padrão: glpi${NC}"
        echo -e "${BLUE}🔐 Senha padrão: glpi${NC}"
        echo ""
        echo -e "${BLUE}🗄️  Banco de dados: mariadb${NC}"
        echo -e "${BLUE}👤 Usuário DB: root${NC}"
        echo -e "${BLUE}🔐 Senha DB: glpi${NC}"
        echo "========================================"
    else
        log_error "❌ Falha na migração do GLPI"
        log_info "📝 Para debug, você pode acessar os containers:"
        echo -e "${YELLOW}docker exec -it $C_MARIADB bash${NC}"
        echo -e "${YELLOW}docker exec -it $C_GLPI bash${NC}"
        exit 1
    fi
}

# Verifica se foi solicitada ajuda
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
    exit 0
fi

# Verifica se o Docker está rodando
if ! docker ps >/dev/null 2>&1; then
    log_error "Docker não está rodando ou não foi encontrado!"
    log_info "Por favor, inicie o Docker e tente novamente."
    exit 1
fi

# Executa a instalação
install_glpi "$1"

log_success "🚀 Script concluído com sucesso!"
