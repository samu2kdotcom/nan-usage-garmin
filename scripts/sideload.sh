#!/usr/bin/env bash
#
# scripts/sideload.sh — instala un .prg en un reloj Garmin conectado por USB (MTP)
# y gestiona sus logs. Pensado para el portátil Linux (GVFS/gvfs-mtp), ver
# DESARROLLO.md.
#
# Uso:
#   scripts/sideload.sh <app.prg> [NombreDestino.prg]   copia a GARMIN/APPS/
#   scripts/sideload.sh --logs-on <app.prg> [...]        además crea GARMIN/APPS/LOGS/<Nombre>.TXT
#                                                        (activa el log de System.println)
#   scripts/sideload.sh --pull-logs <dir>                trae GARMIN/APPS/LOGS/* a <dir>
#   scripts/sideload.sh --where                          imprime la ruta GARMIN del reloj
#
# Entorno:
#   GARMIN_MTP_ROOT   ruta de la carpeta GARMIN ya montada (salta la autodetección)
#
# Tras copiar, DESCONECTA el cable: el reloj verifica e instala la app.
#
set -euo pipefail

log() { printf '[sideload] %s\n' "$*" >&2; }
die() { printf '[sideload] ERROR: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-2}"; }

GVFS_DIR="/run/user/$(id -u)/gvfs"

# Busca la carpeta GARMIN del reloj en los montajes MTP de GVFS (monta si hace falta).
find_garmin_root() {
    if [ -n "${GARMIN_MTP_ROOT:-}" ]; then
        [ -d "$GARMIN_MTP_ROOT/APPS" ] || die "GARMIN_MTP_ROOT='$GARMIN_MTP_ROOT' no contiene APPS/"
        printf '%s\n' "$GARMIN_MTP_ROOT"
        return
    fi
    command -v gio >/dev/null 2>&1 || die "falta 'gio' (paquete glib2) y gvfs-mtp"

    if ! compgen -G "$GVFS_DIR/mtp:host=*" >/dev/null; then
        local uri
        uri="$(gio mount -li 2>/dev/null | sed -n 's/.*activation_root=\(mtp:\/\/[^ ]*\).*/\1/p' | head -n1)"
        [ -n "$uri" ] || die "no veo ningún dispositivo MTP. ¿Cable de datos conectado y reloj desbloqueado? (prueba: mtp-detect)"
        log "montando $uri"
        gio mount "$uri" || die "no se pudo montar $uri (¿otro proceso usa el reloj?)"
        sleep 1
    fi

    local d
    for d in "$GVFS_DIR"/mtp:host=*/*/GARMIN "$GVFS_DIR"/mtp:host=*/GARMIN; do
        [ -d "$d/APPS" ] && { printf '%s\n' "$d"; return; }
    done
    die "montado, pero no encuentro GARMIN/APPS en $GVFS_DIR/mtp:host=* (¿es un Garmin?)"
}

# Copia por la ruta FUSE de GVFS; si falla (MTP no admite todo), usa gio copy.
put() {
    local src="$1" dst="$2"
    cp -f "$src" "$dst" 2>/dev/null || gio copy -f "$src" "$dst"
}

LOGS_ON=0
case "${1:-}" in
    -h|--help) usage 0 ;;
    --where)   find_garmin_root; exit 0 ;;
    --pull-logs)
        OUT="${2:-}"; [ -n "$OUT" ] || usage
        G="$(find_garmin_root)"
        [ -d "$G/APPS/LOGS" ] || die "el reloj no tiene GARMIN/APPS/LOGS"
        mkdir -p "$OUT"
        n=0
        for f in "$G"/APPS/LOGS/*; do
            [ -f "$f" ] || continue
            put "$f" "$OUT/$(basename "$f")"
            n=$((n+1))
        done
        log "$n fichero(s) de log copiados a $OUT"
        exit 0 ;;
    --logs-on) LOGS_ON=1; shift ;;
    "") usage ;;
esac

PRG="${1:-}"
[ -n "$PRG" ] || usage
[ -f "$PRG" ] || die "no existe '$PRG'"
case "$PRG" in *.prg) ;; *) die "'$PRG' no es un .prg" ;; esac
DEST_NAME="${2:-$(basename "$PRG")}"
# los builds personales se instalan con el nombre normal de la app
DEST_NAME="${DEST_NAME%.personal.prg}"; DEST_NAME="${DEST_NAME%.prg}.prg"

G="$(find_garmin_root)"
log "reloj: $G"
put "$PRG" "$G/APPS/$DEST_NAME"
log "copiado: $PRG -> GARMIN/APPS/$DEST_NAME"

if [ "$LOGS_ON" = 1 ]; then
    LOGF="$(basename "$DEST_NAME" .prg).TXT"
    mkdir -p "$G/APPS/LOGS" 2>/dev/null || gio mkdir "$G/APPS/LOGS" 2>/dev/null || true
    if [ ! -e "$G/APPS/LOGS/$LOGF" ]; then
        TMP="$(mktemp)"; : > "$TMP"
        put "$TMP" "$G/APPS/LOGS/$LOGF"; rm -f "$TMP"
        log "log activado: GARMIN/APPS/LOGS/$LOGF"
    else
        log "log ya activo: GARMIN/APPS/LOGS/$LOGF"
    fi
fi

log "OK. Desconecta el cable para que el reloj instale la app."
