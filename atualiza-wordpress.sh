#!/bin/bash
######################################################################################
# ATUALIZADOR WORDPRESS COM BACKUP COMPLETO PARA ISPCONFIG                           #
# Se você utiliza ISPConfig e tem sites em WordPress nele, esse script é para        #
# você. Ele vai criar uma estrutura de pastas em /root chamada Backup-WP e vai       #
# fazer backup por dominio, solicitado o nome do dominio para fazer o Backup do site #
# e banco, mantendo apenas os ultimos 2 backups nesta pasta e atualizar o WordPress, #
# Temas e Plugins.                                                                   #
# Autor: Diego Costa (@diegocostaroot) / Projeto Root (youtube.com/projetoroot)      #
# Versão: 1.0                                                                        #
# Veja o link: https://github.com/projetoroot                                        #
# 2026                                                                               #
######################################################################################
clear
set -euo pipefail

echo "================================================================"
echo "               🔧 Diego Costa (IT Security)"
echo "                 https://github.com/projetoroot                  "
echo "      ATUALIZADOR WORDPRESS COM BACKUP COMPLETO PARA ISPCONFIG   "
echo "================================================================"
echo

read -rp "Digite o domínio (ex: site.com.br): " DOMINIO

DOMINIO=$(echo "$DOMINIO" | tr '[:upper:]' '[:lower:]')

DIR="/var/www/${DOMINIO}/web"

BACKUP_BASE="/root/Backup-WP"
BACKUP_DIR="${BACKUP_BASE}/${DOMINIO}"

mkdir -p "$BACKUP_DIR"

DATA=$(date +"%Y%m%d-%H%M%S")

ARQ_BACKUP="${BACKUP_DIR}/${DOMINIO}-files-${DATA}.tar.gz"
DB_BACKUP="${BACKUP_DIR}/${DOMINIO}-db-${DATA}.sql"
LOG="${BACKUP_DIR}/${DOMINIO}-${DATA}.log"

exec > >(tee -a "$LOG")
exec 2>&1

echo
echo "[INFO] Início: $(date)"
echo

if [ ! -d "$DIR" ]; then
    echo "[ERRO] Diretório não encontrado:"
    echo "$DIR"
    exit 1
fi

if ! command -v wp >/dev/null 2>&1; then
    echo "[ERRO] WP-CLI não encontrado."
    exit 1
fi

echo "[OK] Diretório localizado:"
echo "$DIR"

cd "$DIR"

echo
echo "=========================================================="
echo "INFORMAÇÕES DO SITE"
echo "=========================================================="

WP_VERSION=$(wp core version --allow-root 2>/dev/null || echo "Desconhecida")

echo "WordPress: $WP_VERSION"

echo
echo "Espaço disponível:"
df -h "$BACKUP_DIR"

echo "=========================================================="
echo "BACKUP DO BANCO DE DADOS"
echo "=========================================================="

wp db export "$DB_BACKUP" --allow-root

if [ ! -f "$DB_BACKUP" ]; then
    echo "[ERRO] Falha ao gerar backup do banco."
    exit 1
fi

if [ ! -s "$DB_BACKUP" ]; then
    echo "[ERRO] Backup SQL vazio."
    exit 1
fi

echo "[OK] Banco salvo em:"
echo "$DB_BACKUP"

echo "[INFO] Tamanho do backup do banco:"
du -sh "$DB_BACKUP"


echo "=========================================================="
echo "BACKUP DOS ARQUIVOS"
echo "=========================================================="

REALPATH=$(readlink -f "$DIR")

echo "[INFO] Caminho real do site:"
echo "$REALPATH"

tar --xattrs --acls -czpf "$ARQ_BACKUP" -C "$REALPATH" .

if [ ! -f "$ARQ_BACKUP" ]; then
    echo "[ERRO] Falha ao gerar backup dos arquivos."
    exit 1
fi

echo "[OK] Arquivos salvos em:"
echo "$ARQ_BACKUP"

echo
echo "=========================================================="
echo "VALIDAÇÃO DOS BACKUPS"
echo "=========================================================="

gzip -t "$ARQ_BACKUP"

echo "[OK] Arquivo compactado íntegro."

echo
echo "=========================================================="
echo "ATUALIZAÇÃO DO WORDPRESS"
echo "=========================================================="

wp core update --allow-root

echo
echo "Verificando integridade..."

wp core verify-checksums --allow-root

echo
echo "=========================================================="
echo "ATUALIZAÇÃO DOS PLUGINS"
echo "=========================================================="

PENDENTES_PLUGINS=$(wp plugin list --update=available --format=count --allow-root)

echo "Plugins pendentes antes da atualização: $PENDENTES_PLUGINS"

if [ "$PENDENTES_PLUGINS" -gt 0 ]; then
    wp plugin update --all --allow-root
else
    echo "Nenhum plugin para atualizar."
fi

echo
echo "=========================================================="
echo "ATUALIZAÇÃO DOS TEMAS"
echo "=========================================================="

PENDENTES_TEMAS=$(wp theme list --update=available --format=count --allow-root 2>/dev/null)
PENDENTES_TEMAS=${PENDENTES_TEMAS//[^0-9]/}
PENDENTES_TEMAS=${PENDENTES_TEMAS:-0}

echo "Temas pendentes antes da atualização: $PENDENTES_TEMAS"

if [ "$PENDENTES_TEMAS" -gt 0 ]; then
    wp theme update --all --allow-root
else
    echo "Nenhum tema para atualizar."
fi

echo
echo "=========================================================="
echo "LIMPEZA DE CACHE"
echo "=========================================================="

wp cache flush --allow-root || true

echo
echo "=========================================================="
echo "STATUS FINAL"
echo "=========================================================="

echo
echo "Versão WordPress:"
wp core version --allow-root

echo

PENDENTES_PLUGINS=$(wp plugin list --update=available --format=count --allow-root 2>/dev/null)
PENDENTES_PLUGINS=${PENDENTES_PLUGINS//[^0-9]/}
PENDENTES_PLUGINS=${PENDENTES_PLUGINS:-0}

PENDENTES_TEMAS=$(wp theme list --update=available --format=count --allow-root 2>/dev/null)
PENDENTES_TEMAS=${PENDENTES_TEMAS//[^0-9]/}
PENDENTES_TEMAS=${PENDENTES_TEMAS:-0}

echo "Plugins pendentes: $PENDENTES_PLUGINS"

if [ "$PENDENTES_PLUGINS" -gt 0 ]; then
    wp plugin list --update=available --allow-root
fi

echo
echo "Temas pendentes: $PENDENTES_TEMAS"

if [ "$PENDENTES_TEMAS" -gt 0 ]; then
    wp theme list --update=available --allow-root
fi

echo
echo "Integridade:"
wp core verify-checksums --allow-root

echo
echo "=========================================================="
echo "LIMPEZA DE BACKUPS ANTIGOS"
echo "=========================================================="

mapfile -t BACKUP_LIST < <(
    ls -1t "$BACKUP_DIR"/*-db-*.sql 2>/dev/null | head -n 2
)

echo "[INFO] Mantendo os 2 backups mais recentes..."

KEEP_TS=()

for FILE in "${BACKUP_LIST[@]}"; do
    TS=$(basename "$FILE" | sed -E 's/.*-db-([0-9]{8}-[0-9]{6})\.sql/\1/')
    KEEP_TS+=("$TS")
done

if [ "${#BACKUP_LIST[@]}" -eq 0 ]; then
    echo "[INFO] Nenhum backup encontrado para limpeza."
else

    for FILE in "$BACKUP_DIR"/*-db-*.sql; do

        [ -e "$FILE" ] || continue

        TS=$(basename "$FILE" | sed -E 's/.*-db-([0-9]{8}-[0-9]{6})\.sql/\1/')

        KEEP=false

        for K in "${KEEP_TS[@]}"; do
            if [ "$TS" = "$K" ]; then
                KEEP=true
                break
            fi
        done

        if [ "$KEEP" = false ]; then
            echo "[REMOVENDO] $TS"
            rm -f "$BACKUP_DIR"/*"$TS"*
        fi

    done
fi

echo "[OK] Limpeza concluída. Mantidos os 2 backups mais recentes."

echo
echo "=========================================================="
echo "RESUMO"
echo "=========================================================="

echo "Domínio........: $DOMINIO"
echo "Diretório......: $DIR"
echo "Backup banco...: $DB_BACKUP"
echo "Backup arquivos: $ARQ_BACKUP"
echo "Log............: $LOG"
sha256sum "$ARQ_BACKUP" > "${ARQ_BACKUP}.sha256"
sha256sum "$DB_BACKUP" > "${DB_BACKUP}.sha256"
echo "Hash arquivos..: $(basename "${ARQ_BACKUP}.sha256")"
echo "Hash banco.....: $(basename "${DB_BACKUP}.sha256")"
TAM_ARQUIVOS=$(du -sh "$ARQ_BACKUP" | awk '{print $1}')
TAM_BANCO=$(du -sh "$DB_BACKUP" | awk '{print $1}')
echo "Tam. arquivos..: $TAM_ARQUIVOS"
echo "Tam. banco.....: $TAM_BANCO"
echo
echo "Finalizado em..: $(date)"

echo
echo "[SUCESSO] Atualização concluída."
echo
