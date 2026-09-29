#!/usr/bin/env bash
# ============================================================
# MediaWiki Installer - Projeto Root
#
# Debian 13
# MySQL 8.4 LTS
# MediaWiki - última versão estável
# Apache
# PHP
# YouTube Extension
# ImageMagick
# FFmpeg
#
# Autor: Diego Costa (@diegocostaroot) / Projeto Root (youtube.com/projetoroot)         
# Versão: 1.0                                                                           
# 2026                                                                                  
# 
# Referências:
# https://www.mediawiki.org/wiki/MediaWiki
# https://dev.mysql.com/downloads/repo/apt/
# ============================================================

set -Eeuo pipefail

# ============================================================
# CONFIGURAÇÕES
# ============================================================

MEDIAWIKI_DIR="/var/www/wiki"

DB_NAME="wikidb"
DB_USER="mediawiki"

APACHE_SITE="mediawiki.conf"

WIKI_LANGUAGE="pt-br"

LOG_FILE="/var/log/mediawiki-install.log"
INSTALL_INFO="${MEDIAWIKI_DIR}/INSTALL-INFO.txt"

MYSQL_SERIES="mysql-8.4-lts"

USE_DNS="no"
WEB_DOMAIN=""
SERVER_IP=""
WIKI_URL=""

WIKI_NAME=""
WIKI_ADMIN=""

DB_PASSWORD=""
ADMIN_PASSWORD=""

ENABLE_HTTPS="no"

MEDIAWIKI_VERSION=""
MEDIAWIKI_MAJOR=""
MEDIAWIKI_BRANCH=""
MEDIAWIKI_URL=""

MYSQL_APT_URL=""
MYSQL_APT_FILE=""

# ============================================================
# CORES
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# LOG
# ============================================================

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[AVISO]${NC} $*"
}

error() {
    echo -e "${RED}[ERRO]${NC} $*"
}

trap 'error "Falha na linha $LINENO. Comando: $BASH_COMMAND"' ERR

# ============================================================
# BANNER
# ============================================================

show_banner() {

    clear 2>/dev/null || true

    echo
    echo "============================================================"
    echo "          MEDIAWIKI INSTALLER - PROJETO ROOT"
    echo "============================================================"
    echo
    echo "Debian 13"
    echo "MySQL 8.4 LTS"
    echo "MediaWiki - última versão estável"
    echo "Extension: YouTube"
    echo "ImageMagick"
    echo "FFmpeg"
    echo
    echo "============================================================"
    echo
}

# ============================================================
# VALIDAÇÕES INICIAIS
# ============================================================

check_root() {

    if [[ "$EUID" -ne 0 ]]; then
        error "Este instalador deve ser executado como root."
        exit 1
    fi

    ok "Execução como root confirmada."
}

check_debian() {

    if [[ ! -f /etc/os-release ]]; then
        error "Não foi possível identificar o sistema operacional."
        exit 1
    fi

    source /etc/os-release

    if [[ "${ID:-}" != "debian" ]]; then
        error "Este instalador requer Debian 13."
        exit 1
    fi

    if [[ "${VERSION_ID:-}" != "13" ]]; then
        warning "Sistema detectado: ${PRETTY_NAME}"
        warning "O instalador foi desenvolvido para Debian 13."
    else
        ok "Sistema operacional: ${PRETTY_NAME}"
    fi
}

check_architecture() {

    local architecture

    architecture="$(dpkg --print-architecture)"

    if [[ "$architecture" != "amd64" ]]; then
        error "Arquitetura não suportada: $architecture"
        error "Este instalador suporta amd64."
        exit 1
    fi

    info "Arquitetura detectada: $architecture"
}

# ============================================================
# DETECTAR IP
# ============================================================

detect_server_ip() {

    SERVER_IP="$(
        ip -4 route get 1.1.1.1 2>/dev/null |
        awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i == "src") {
                    print $(i+1)
                    exit
                }
            }
        }'
    )"

    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP="$(hostname -I | awk '{print $1}')"
    fi

    if [[ -z "$SERVER_IP" ]]; then
        error "Não foi possível detectar o endereço IPv4 do servidor."
        exit 1
    fi
}

# ============================================================
# VALIDAR DNS
# ============================================================

validate_domain() {

    if [[ ! "$WEB_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        warning "Nome DNS inválido."
        return 1
    fi

    return 0
}

# ============================================================
# COLETAR DADOS DA WIKI
# ============================================================

collect_wiki_information() {

    echo
    echo "============================================================"
    echo " CONFIGURAÇÃO DA WIKI"
    echo "============================================================"
    echo

    while true; do

        read -rp "Nome da Wiki: " WIKI_NAME

        if [[ -n "$WIKI_NAME" ]]; then
            break
        fi

        warning "O nome da Wiki não pode ficar vazio."

    done

    echo

    read -rp "Usuário administrador [admin]: " WIKI_ADMIN

    WIKI_ADMIN="${WIKI_ADMIN:-admin}"

    if [[ ! "$WIKI_ADMIN" =~ ^[A-Za-z0-9._-]+$ ]]; then
        error "Nome de usuário administrador inválido."
        exit 1
    fi

    echo

    while true; do

        read -rsp "Senha do administrador (mínimo 12 caracteres): " ADMIN_PASSWORD
        echo

        if (( ${#ADMIN_PASSWORD} >= 12 )); then
            break
        fi

        warning "A senha deve possuir pelo menos 12 caracteres."

    done

    while true; do

        read -rsp "Confirme a senha do administrador: " ADMIN_PASSWORD_CONFIRM
        echo

        if [[ "$ADMIN_PASSWORD" == "$ADMIN_PASSWORD_CONFIRM" ]]; then
            break
        fi

        warning "As senhas não coincidem."

    done

    unset ADMIN_PASSWORD_CONFIRM

    echo
    echo "============================================================"
    echo " ACESSO À WIKI"
    echo "============================================================"
    echo

    read -rp "Possui DNS para a Wiki? [s/N]: " DNS_ANSWER

    DNS_ANSWER="${DNS_ANSWER:-N}"

    if [[ "$DNS_ANSWER" =~ ^[SsYy]$ ]]; then

        USE_DNS="yes"

        while true; do

            read -rp "Hostname DNS (ex.: wiki.exemplo.com.br): " WEB_DOMAIN

            if validate_domain; then
                break
            fi

        done

        WIKI_URL="http://${WEB_DOMAIN}"

    else

        USE_DNS="no"

        detect_server_ip

        WEB_DOMAIN="$SERVER_IP"
        WIKI_URL="http://${SERVER_IP}"

        info "IPv4 detectado: $SERVER_IP"
    fi

    echo

    if [[ "$USE_DNS" == "yes" ]]; then

        read -rp "Deseja habilitar HTTPS com Let's Encrypt? [s/N]: " HTTPS_ANSWER

        HTTPS_ANSWER="${HTTPS_ANSWER:-N}"

        if [[ "$HTTPS_ANSWER" =~ ^[SsYy]$ ]]; then
            ENABLE_HTTPS="yes"
        fi

    else

        ENABLE_HTTPS="no"

        info "HTTPS automático disponível somente quando DNS é utilizado."

    fi
}

# ============================================================
# RESUMO E CONFIRMAÇÃO
# ============================================================

show_configuration() {

    echo
    echo "============================================================"
    echo " CONFIGURAÇÃO INFORMADA"
    echo "============================================================"
    echo
    echo "Nome da Wiki:       $WIKI_NAME"
    echo "Administrador:      $WIKI_ADMIN"
    echo "DNS:                $USE_DNS"
    echo "Hostname/IP:        $WEB_DOMAIN"
    echo "URL inicial:        $WIKI_URL"
    echo "HTTPS:              $ENABLE_HTTPS"
    echo "Banco:              MySQL 8.4 LTS"
    echo "Idioma:             $WIKI_LANGUAGE"
    echo
    echo "A senha do administrador não será exibida."
    echo
    echo "============================================================"
    echo
}

confirm_installation() {

    local answer

    read -rp "As informações estão corretas e deseja iniciar a instalação? [s/N]: " answer

    answer="${answer:-N}"

    if [[ ! "$answer" =~ ^[SsYy]$ ]]; then
        echo
        warning "Instalação cancelada pelo usuário."
        exit 0
    fi

    echo
    info "Iniciando instalação..."
    echo
}

# ============================================================
# DEPENDÊNCIAS
# ============================================================

install_base_packages() {

    info "Atualizando os repositórios do Debian..."

    apt-get update

    info "Instalando dependências básicas..."

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        apache2 \
        php \
        php-cli \
        php-common \
        php-mysql \
        php-xml \
        php-intl \
        php-mbstring \
        php-apcu \
        php-curl \
        php-gd \
        php-bcmath \
        php-zip \
        php-opcache \
        unzip \
        wget \
        curl \
        git \
        ca-certificates \
        gnupg \
        debconf-utils \
        openssl \
        imagemagick \
        ffmpeg \
        lsb-release

    ok "Dependências básicas instaladas."
}

# ============================================================
# PHP
# ============================================================

check_php() {

    local php_version

    php_version="$(
        php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;'
    )"

    if [[ "$(printf '%s\n' "8.3" "$php_version" | sort -V | head -n1)" != "8.3" ]]; then

        error "PHP $php_version não atende ao requisito do MediaWiki."

        error "O MediaWiki atual requer PHP 8.3 ou superior."

        exit 1
    fi

    ok "PHP $php_version detectado."
}

# ============================================================
# MEDIAWIKI
# ============================================================

get_latest_mediawiki() {

    local page

    info "Consultando a versão estável do MediaWiki..."

    page="$(
        curl -fsSL \
            --retry 3 \
            --connect-timeout 15 \
            https://www.mediawiki.org/wiki/Download/en
    )"

    MEDIAWIKI_VERSION="$(
        printf '%s' "$page" |
        grep -oE 'MediaWiki [0-9]+\.[0-9]+\.[0-9]+ \(stable\)' |
        head -n 1 |
        grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
    )"

    if [[ -z "$MEDIAWIKI_VERSION" ]]; then

        error "Não foi possível detectar a versão estável do MediaWiki."

        exit 1
    fi

    MEDIAWIKI_MAJOR="${MEDIAWIKI_VERSION%.*}"

    MEDIAWIKI_BRANCH="REL${MEDIAWIKI_MAJOR//./_}"

    MEDIAWIKI_URL="https://releases.wikimedia.org/mediawiki/${MEDIAWIKI_MAJOR}/mediawiki-${MEDIAWIKI_VERSION}.tar.gz"

    ok "MediaWiki $MEDIAWIKI_VERSION detectado."

    info "Branch das extensões: $MEDIAWIKI_BRANCH"

    info "URL do pacote: $MEDIAWIKI_URL"
}

download_mediawiki() {

    local mediawiki_file

    mediawiki_file="/tmp/mediawiki-${MEDIAWIKI_VERSION}.tar.gz"

    info "Baixando MediaWiki $MEDIAWIKI_VERSION..."

    wget \
        --show-progress \
        -O "$mediawiki_file" \
        "$MEDIAWIKI_URL"

    info "Validando pacote..."

    tar -tzf "$mediawiki_file" >/dev/null

    ok "MediaWiki $MEDIAWIKI_VERSION baixado e validado."
}

# ============================================================
# MYSQL APT REPOSITORY
# ============================================================

get_mysql_apt_package() {

    local page
    local package_name

    info "Consultando o MySQL APT Repository..."

    page="$(
        curl -fsSL \
            --retry 3 \
            --connect-timeout 15 \
            https://dev.mysql.com/downloads/repo/apt/
    )"

    package_name="$(
        printf '%s' "$page" |
        grep -oE 'mysql-apt-config_[0-9]+\.[0-9]+\.[0-9]+-[0-9]+_all\.deb' |
        sort -Vu |
        tail -n 1
    )"

    if [[ -z "$package_name" ]]; then

        error "Não foi possível identificar o pacote mysql-apt-config."

        error "Verifique a página oficial do MySQL APT Repository."

        exit 1
    fi

    MYSQL_APT_URL="https://dev.mysql.com/get/${package_name}"

    MYSQL_APT_FILE="/tmp/${package_name}"

    info "Pacote encontrado: $package_name"
}

# ============================================================
# INSTALAR MYSQL APT REPOSITORY
# ============================================================

install_mysql_repository() {

    get_mysql_apt_package

    info "Baixando mysql-apt-config..."

    wget \
        --show-progress \
        -O "$MYSQL_APT_FILE" \
        "$MYSQL_APT_URL"

    info "Configurando MySQL 8.4 LTS..."

    echo "mysql-apt-config mysql-apt-config/select-server select ${MYSQL_SERIES}" |
        debconf-set-selections

    DEBIAN_FRONTEND=noninteractive \
        dpkg -i "$MYSQL_APT_FILE" || true

    apt-get install -f -y

    info "Atualizando informações dos repositórios MySQL..."

    apt-get update

    ok "MySQL APT Repository configurado."
}

# ============================================================
# MYSQL
# ============================================================

install_mysql() {

    info "Instalando MySQL 8.4 LTS..."

    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y \
        mysql-server \
        mysql-client

    systemctl enable mysql

    systemctl start mysql

    if ! systemctl is-active --quiet mysql; then

        error "O serviço MySQL não está ativo."

        systemctl status mysql --no-pager || true

        exit 1
    fi

    local mysql_version

    mysql_version="$(mysql --version)"

    echo
    echo "Versão detectada:"
    echo "$mysql_version"
    echo

    if [[ ! "$mysql_version" =~ 8\.4\.[0-9]+ ]]; then

        error "A versão instalada não é MySQL 8.4.x."

        error "Versão encontrada: $mysql_version"

        exit 1
    fi

    ok "MySQL 8.4 LTS instalado."
}

# ============================================================
# SENHA DO BANCO
# ============================================================

generate_db_password() {

    DB_PASSWORD="$(
        openssl rand -base64 48 |
        tr -dc 'A-Za-z0-9@#%+=_' |
        head -c 32
    )"

    if [[ "${#DB_PASSWORD}" -lt 20 ]]; then

        error "Não foi possível gerar uma senha segura para o banco."

        exit 1
    fi
}

# ============================================================
# BANCO DE DADOS
# ============================================================

configure_database() {

    local mysql_client_file

    mysql_client_file="$(mktemp)"
    chmod 600 "$mysql_client_file"

    cat > "$mysql_client_file" <<MYSQL_CNF
[client]
user=${DB_USER}
password=${DB_PASSWORD}
database=${DB_NAME}
protocol=socket
MYSQL_CNF

    info "Criando banco de dados MediaWiki..."

    mysql \
        --protocol=socket \
        -uroot \
        <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost'
IDENTIFIED BY '${DB_PASSWORD}';

ALTER USER '${DB_USER}'@'localhost'
IDENTIFIED BY '${DB_PASSWORD}';

GRANT ALL PRIVILEGES
ON \`${DB_NAME}\`.*
TO '${DB_USER}'@'localhost';

FLUSH PRIVILEGES;
SQL

    mysql \
        --defaults-extra-file="$mysql_client_file" \
        -e "SELECT 1;" >/dev/null

    rm -f "$mysql_client_file"

    ok "Banco de dados configurado."
}

# ============================================================
# MEDIAWIKI
# ============================================================

install_mediawiki() {

    local mediawiki_file
    local extracted_dir

    mediawiki_file="/tmp/mediawiki-${MEDIAWIKI_VERSION}.tar.gz"

    extracted_dir="/tmp/mediawiki-${MEDIAWIKI_VERSION}"

    info "Instalando MediaWiki em $MEDIAWIKI_DIR..."

    rm -rf "$MEDIAWIKI_DIR"
    rm -rf "$extracted_dir"

    mkdir -p "$MEDIAWIKI_DIR"

    tar \
        -xzf "$mediawiki_file" \
        -C /tmp

    if [[ ! -d "$extracted_dir" ]]; then

        error "Diretório do MediaWiki não foi encontrado após a extração."

        exit 1
    fi

    rm -rf "$MEDIAWIKI_DIR"

    mv "$extracted_dir" "$MEDIAWIKI_DIR"

    mkdir -p "$MEDIAWIKI_DIR/images"

    chown -R www-data:www-data "$MEDIAWIKI_DIR"

    ok "MediaWiki instalado em $MEDIAWIKI_DIR."
}

# ============================================================
# PHP
# ============================================================

configure_php() {

    local cli_php_ini
    local apache_php_ini
    local php_mm

    php_mm="$(
        php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;'
    )"

    info "Configurando módulo PHP do Apache..."

    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y "libapache2-mod-php${php_mm}"

    a2dismod mpm_event >/dev/null 2>&1 || true
    a2dismod mpm_worker >/dev/null 2>&1 || true

    a2enmod mpm_prefork >/dev/null

    a2enmod "php${php_mm}"
    #a2enmod "php${php_mm}" >/dev/null 2>&1 || true

    cli_php_ini="$(php -r 'echo php_ini_loaded_file();')"

    if [[ -z "$cli_php_ini" || ! -f "$cli_php_ini" ]]; then
        error "Não foi possível localizar o php.ini do PHP CLI."
        exit 1
    fi

    apache_php_ini="$(
        find /etc/php -type f -path '*/apache2/php.ini' 2>/dev/null |
        sort -V |
        tail -n 1
    )"

    if [[ -z "$apache_php_ini" || ! -f "$apache_php_ini" ]]; then
        error "Não foi possível localizar o php.ini do PHP Apache."
        exit 1
    fi

    info "Configurando PHP CLI..."
    info "Arquivo: $cli_php_ini"

    sed -i \
        -E \
        's/^[;[:space:]]*memory_limit[[:space:]]*=.*/memory_limit = 256M/;
         s/^[;[:space:]]*upload_max_filesize[[:space:]]*=.*/upload_max_filesize = 64M/;
         s/^[;[:space:]]*post_max_size[[:space:]]*=.*/post_max_size = 64M/;
         s/^[;[:space:]]*max_execution_time[[:space:]]*=.*/max_execution_time = 120/;
         s/^[;[:space:]]*max_input_time[[:space:]]*=.*/max_input_time = 120/' \
        "$cli_php_ini"

    info "Configurando PHP Apache..."
    info "Arquivo: $apache_php_ini"

    sed -i \
        -E \
        's/^[;[:space:]]*memory_limit[[:space:]]*=.*/memory_limit = 256M/;
         s/^[;[:space:]]*upload_max_filesize[[:space:]]*=.*/upload_max_filesize = 64M/;
         s/^[;[:space:]]*post_max_size[[:space:]]*=.*/post_max_size = 64M/;
         s/^[;[:space:]]*max_execution_time[[:space:]]*=.*/max_execution_time = 120/;
         s/^[;[:space:]]*max_input_time[[:space:]]*=.*/max_input_time = 120/' \
        "$apache_php_ini"

    systemctl restart apache2

    if ! apache2ctl -M 2>/dev/null | grep -q 'php.*_module'; then
        error "O módulo PHP do Apache não está carregado."
        exit 1
    fi

    ok "PHP configurado."
}

# ============================================================
# APACHE
# ============================================================

configure_apache() {

    info "Configurando Apache..."

    a2enmod rewrite >/dev/null
    a2enmod headers >/dev/null
    a2enmod expires >/dev/null

    cat > "/etc/apache2/conf-available/servername.conf" <<EOF
ServerName ${WEB_DOMAIN}
EOF

    a2enconf servername >/dev/null

    cat > "/etc/apache2/sites-available/${APACHE_SITE}" <<APACHE
<VirtualHost *:80>

    ServerName ${WEB_DOMAIN}

    DocumentRoot ${MEDIAWIKI_DIR}

    <Directory ${MEDIAWIKI_DIR}>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <Directory ${MEDIAWIKI_DIR}/images>
        Options -Indexes -ExecCGI
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch "^(LocalSettings\.php|INSTALL-INFO\.txt)$">
        Require all denied
    </FilesMatch>

    DirectoryIndex index.php

    ErrorLog \${APACHE_LOG_DIR}/mediawiki_error.log

    CustomLog \${APACHE_LOG_DIR}/mediawiki_access.log combined

</VirtualHost>
APACHE

    a2dissite 000-default.conf >/dev/null 2>&1 || true

    a2ensite "$APACHE_SITE" >/dev/null

    apache2ctl configtest

    systemctl enable apache2

    systemctl restart apache2

    ok "Apache configurado."
}

# ============================================================
# YOUTUBE
# ============================================================

install_youtube() {

    local extension_dir

    extension_dir="${MEDIAWIKI_DIR}/extensions/YouTube"

    info "Instalando extensão YouTube..."

    rm -rf "$extension_dir"

    mkdir -p "${MEDIAWIKI_DIR}/extensions"

    if git ls-remote \
        --exit-code \
        --heads \
        https://gerrit.wikimedia.org/r/mediawiki/extensions/YouTube.git \
        "$MEDIAWIKI_BRANCH" >/dev/null 2>&1; then

        info "Branch compatível encontrada: $MEDIAWIKI_BRANCH"

        git clone \
            --depth 1 \
            --branch "$MEDIAWIKI_BRANCH" \
            https://gerrit.wikimedia.org/r/mediawiki/extensions/YouTube.git \
            "$extension_dir"

    else

        warning "Branch $MEDIAWIKI_BRANCH não encontrada."

        warning "Utilizando a branch padrão da extensão YouTube."

        git clone \
            --depth 1 \
            https://gerrit.wikimedia.org/r/mediawiki/extensions/YouTube.git \
            "$extension_dir"

    fi

    chown -R www-data:www-data "$extension_dir"

    ok "Extensão YouTube instalada."
}

# ============================================================
# INSTALAÇÃO DO MEDIAWIKI
# ============================================================

install_mediawiki_database() {

    local db_password_file
    local admin_password_file

    db_password_file="$(mktemp)"
    admin_password_file="$(mktemp)"

    chmod 600 "$db_password_file"
    chmod 600 "$admin_password_file"

    printf '%s\n' "$DB_PASSWORD" > "$db_password_file"

    printf '%s\n' "$ADMIN_PASSWORD" > "$admin_password_file"

    info "Configurando o MediaWiki..."

    cd "$MEDIAWIKI_DIR"

    php maintenance/run.php install \
        --dbname="$DB_NAME" \
        --dbserver="localhost" \
        --dbtype="mysql" \
        --dbuser="$DB_USER" \
        --dbpassfile="$db_password_file" \
        --installdbuser="root" \
        --server="$WIKI_URL" \
        --scriptpath="" \
        --lang="$WIKI_LANGUAGE" \
        --passfile="$admin_password_file" \
        --skins="Vector" \
        "$WIKI_NAME" \
        "$WIKI_ADMIN"

    rm -f "$db_password_file"
    rm -f "$admin_password_file"

    if [[ ! -f "${MEDIAWIKI_DIR}/LocalSettings.php" ]]; then

        error "LocalSettings.php não foi criado."

        exit 1
    fi

    ok "MediaWiki configurado."
}

# ============================================================
# LOCALSETTINGS
# ============================================================

configure_localsettings() {

    info "Configurando extensões e uploads..."

    cat >> "${MEDIAWIKI_DIR}/LocalSettings.php" <<'PHP'

# ============================================================
# Projeto Root - Configurações adicionais
# ============================================================

wfLoadExtension( 'YouTube' );

$wgEnableUploads = true;

$wgUseImageMagick = true;

$wgImageMagickConvertCommand = '/usr/bin/convert';

PHP

    chown www-data:www-data "${MEDIAWIKI_DIR}/LocalSettings.php"

    chmod 600 "${MEDIAWIKI_DIR}/LocalSettings.php"

    ok "LocalSettings.php configurado."
}

# ============================================================
# IMAGENS
# ============================================================

configure_images() {

    mkdir -p "${MEDIAWIKI_DIR}/images"

    chown -R www-data:www-data "${MEDIAWIKI_DIR}/images"

    chmod 755 "${MEDIAWIKI_DIR}/images"

    cat > "${MEDIAWIKI_DIR}/images/.htaccess" <<'HTACCESS'
Options -Indexes
<FilesMatch "\.(php|php[0-9]?|phtml|phar|cgi|pl|py|sh)$">
    Require all denied
</FilesMatch>
HTACCESS

    chown www-data:www-data "${MEDIAWIKI_DIR}/images/.htaccess"

    chmod 644 "${MEDIAWIKI_DIR}/images/.htaccess"

    ok "Diretório de uploads configurado."
}

# ============================================================
# HTTPS
# ============================================================

configure_https() {

    if [[ "$ENABLE_HTTPS" != "yes" ]]; then

        return 0
    fi

    info "Instalando Certbot..."

    apt-get install -y \
        certbot \
        python3-certbot-apache

    info "Configurando certificado Let's Encrypt..."

    certbot \
        --apache \
        --non-interactive \
        --agree-tos \
        --redirect \
        --register-unsafely-without-email \
        -d "$WEB_DOMAIN"

    WIKI_URL="https://${WEB_DOMAIN}"

    ok "HTTPS configurado."
}

# ============================================================
# ATUALIZAÇÃO DO BANCO
# ============================================================

update_mediawiki_database() {

    info "Verificando banco de dados do MediaWiki..."

    cd "$MEDIAWIKI_DIR"

    php maintenance/run.php update --quick

    ok "Banco de dados atualizado."
}

# ============================================================
# TESTES
# ============================================================

run_tests() {

    info "Executando testes finais..."

    if ! systemctl is-active --quiet apache2; then
        error "Apache não está ativo."
        exit 1
    fi

    if ! systemctl is-active --quiet mysql; then
        error "MySQL não está ativo."
        exit 1
    fi

    php -v >/dev/null

    convert -version >/dev/null

    ffmpeg -version >/dev/null

    if [[ ! -f "${MEDIAWIKI_DIR}/index.php" ]]; then
        error "index.php não encontrado."
        exit 1
    fi

    if [[ ! -f "${MEDIAWIKI_DIR}/LocalSettings.php" ]]; then
        error "LocalSettings.php não encontrado."
        exit 1
    fi

    if [[ ! -f "${MEDIAWIKI_DIR}/extensions/YouTube/extension.json" ]]; then
        error "Extensão YouTube não encontrada."
        exit 1
    fi

    if [[ ! -d "${MEDIAWIKI_DIR}/images" ]]; then
        error "Diretório de imagens não encontrado."
        exit 1
    fi

    if [[ ! -f "${MEDIAWIKI_DIR}/images/.htaccess" ]]; then
        error "Arquivo de proteção do diretório de imagens não encontrado."
        exit 1
    fi

    if ! apache2ctl -M 2>/dev/null | grep -q 'php.*_module'; then
        error "Módulo PHP do Apache não está carregado."
        exit 1
    fi

    mysql \
        --protocol=socket \
        -uroot \
        -e "SELECT 1;" >/dev/null

    ok "Todos os testes foram concluídos."
}

# ============================================================
# INFORMAÇÕES DA INSTALAÇÃO
# ============================================================

create_installation_info() {

    mkdir -p "$MEDIAWIKI_DIR"

    cat > "$INSTALL_INFO" <<INFO
============================================================
Projeto Root - MediaWiki Installer
============================================================

Data:
$(date '+%Y-%m-%d %H:%M:%S %z')

MediaWiki:
${MEDIAWIKI_VERSION}

URL:
${WIKI_URL}

Nome da Wiki:
${WIKI_NAME}

Administrador:
${WIKI_ADMIN}

MySQL:
$(mysql -Nse 'SELECT VERSION()')

Banco de dados:
${DB_NAME}

Usuário do banco:
${DB_USER}

Senha do banco:
${DB_PASSWORD}

HTTPS:
${ENABLE_HTTPS}

Diretório:
${MEDIAWIKI_DIR}

Log:
${LOG_FILE}

============================================================
INFO

    chown root:root "$INSTALL_INFO"

    chmod 600 "$INSTALL_INFO"

    ok "Informações da instalação armazenadas em:"
    echo "    $INSTALL_INFO"
}

# ============================================================
# RESUMO FINAL
# ============================================================

show_summary() {

    echo
    echo "============================================================"
    echo "              INSTALAÇÃO CONCLUÍDA"
    echo "============================================================"
    echo
    echo "Wiki:"
    echo "    $WIKI_NAME"
    echo
    echo "MediaWiki:"
    echo "    $MEDIAWIKI_VERSION"
    echo
    echo "URL:"
    echo "    $WIKI_URL"
    echo
    echo "Administrador:"
    echo "    $WIKI_ADMIN"
    echo
    echo "Banco:"
    echo "    $DB_NAME"
    echo
    echo "Usuário DB:"
    echo "    $DB_USER"
    echo
    echo "Senha DB:"
    echo "    armazenada em $INSTALL_INFO"
    echo
    echo "Informações:"
    echo "    $INSTALL_INFO"
    echo
    echo "Log:"
    echo "    $LOG_FILE"
    echo
    echo "============================================================"
    echo
    echo "Acesse a Wiki em:"
    echo
    echo "    $WIKI_URL"
    echo
    echo "============================================================"
    echo
}

# ============================================================
# MAIN
# ============================================================

main() {

    show_banner

    check_root

    check_debian

    check_architecture

    # --------------------------------------------------------
    # IMPORTANTE:
    # Todas as informações são solicitadas ANTES de qualquer
    # instalação ou alteração no sistema.
    # --------------------------------------------------------

    collect_wiki_information

    show_configuration

    confirm_installation

    # --------------------------------------------------------
    # A partir daqui começa a instalação.
    # --------------------------------------------------------

    install_base_packages

    check_php

    get_latest_mediawiki

    generate_db_password

    download_mediawiki

    install_mysql_repository

    install_mysql

    configure_database

    install_mediawiki

    configure_php

    configure_apache

    install_youtube

    install_mediawiki_database

    configure_localsettings

    configure_images

    configure_https

    update_mediawiki_database

    run_tests

    create_installation_info

    show_summary
}

main "$@"
