# GLPI Migration Tool - Migração GLPI 9.x para 10.0.18

Este projeto automatiza a migração do GLPI de versões 9.x para a versão 10.0.18 utilizando Docker containers.

## 📋 Pré-requisitos

- Docker instalado e em execução
- Git instalado
- Backup do banco de dados GLPI em formato SQL
- Acesso root/sudo no sistema

## 🚀 Como usar

### 1. Clone o repositório

```bash
git clone https://github.com/viniciusfbs/glpi9to10
cd glpi9to10/
```

### 2. Prepare o arquivo de backup

**IMPORTANTE**: O arquivo de backup deve estar nomeado como `glpi25.sql` no diretório raiz do projeto.

```bash
# Renomeie seu backup para o nome esperado
mv seu_backup.sql glpi25.sql
```

### 3. Execute a migração

```bash
# Torne o script executável
chmod +x install_full.sh

# Execute a migração (substitua 'glpi_nome' pelo nome desejado para sua instância)
./install_full.sh glpi_nome
```

## 🔧 Processo de Migração

O script realiza automaticamente as seguintes etapas:

1. **Preparação do ambiente**:
   - Criação de diretórios necessários
   - Build das imagens Docker

2. **Container MariaDB**:
   - Configuração do banco de dados
   - Restauração do backup fornecido

3. **Container GLPI 9.4.4**:
   - Instalação do GLPI 9.4.4
   - Aplicação de correções no banco de dados
   - Atualização para versão 9.4.4

4. **Container GLPI 10.0.18**:
   - Build da imagem GLPI 10
   - Instalação do GLPI 10.0.18
   - Preparação para migração final

## 🌐 Acesso aos Sistemas

### GLPI 9.4.4 (Temporário)
- **URL**: http://localhost:2610/glpi
- **Porta**: 2610
- **Status**: Container temporário para migração

### GLPI 10.0.18 (Final)
- **URL**: http://localhost:2611/
- **Porta**: 2611
- **Usuário**: glpi
- **Senha**: glpi

### Banco de dados
- **Host**: localhost
- **Porta**: 3306
- **Usuário**: root
- **Senha**: glpi
- **Database**: glpi

## ⚠️ Importantes Observações

### Portas Fixas
As portas estão fixadas no código:
- **2610**: GLPI 9.4.4 (temporário)
- **2611**: GLPI 10.0.18 (final)
- **3306**: MariaDB

Para personalizar as portas, você precisará modificar os arquivos de script.

### Limpeza Pós-Migração
Após a migração bem-sucedida, você deve **remover o container temporário** do GLPI 9.4.4:

```bash
# Remover container GLPI 9.4.4 (temporário)
docker stop glpi_glpi_nome
docker rm glpi_glpi_nome

# Remover imagem temporária (opcional)
docker rmi glpi_glpi_nome_imagem
```

### Containers Finais
Após a limpeza, você terá apenas os containers necessários:
- `mariadb-glpi_nome` (Banco de dados)
- `glpi10_glpi_nome` (GLPI 10.0.18)

## 📁 Estrutura de Diretórios Criados

```
/var/lib/mysql-glpi_nome/     # Dados do MariaDB
/var/glpi-glpi_nome-dir/      # Arquivos do GLPI
/var/glpi_nome/               # Diretório base da instância
```

## 🛠️ Solução de Problemas

### Arquivo de backup não encontrado
```
❌ Nenhum arquivo de backup encontrado!
```
**Solução**: Certifique-se de que o arquivo `glpi25.sql` está no diretório raiz do projeto.


### Conflito de portas
Se as portas 2610, 2611 ou 3306 estiverem em uso, você precisará:
1. Parar os serviços que estão usando essas portas, ou
2. Modificar as portas nos scripts

