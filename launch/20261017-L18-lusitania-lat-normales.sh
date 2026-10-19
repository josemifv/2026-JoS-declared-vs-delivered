#!/usr/bin/env bash
# T53 — L18 (parte B): latencia (8 B) y ancho de banda (4 MiB) de OSU entre nodos NORMALES de
# Lusitania us63, sin el nodo de referencia de la criba (s02r1b01); responde a Codex 3 y Opus M3/M6.
# Órdenes: informes/ordenes/2026-10-17-T53-triad-binding-v2.md (parte B) y
# informes/ordenes/2026-10-17-T53-triad-binding-v3.md (-m 8:8, -m 4194304:4194304, 00:30:00).
# Separado de L17 (parte A). NO ENVÍA NADA hasta que la persona firme este fichero por su
# sha256 completo (arnés, regla 3).
# Pares (2 trabajos exclusivos de 2 nodos, en paralelo, sin dependencias):
#   P1: s02r1b09 + s02r1b17      P2: s02r2b03 + s02r2b05
# Por trabajo: 11 rondas de osu_latency -m 8:8 y 11 de osu_bw -m 4194304:4194304; la primera de
# cada prueba es de calentamiento; iteraciones y calentamiento internos de OSU sin cambios.
# Binarios, módulos, variables y comprobación de transporte (check_result) = los de la criba de
# us63 (equiv-us63-v2.sbatch, sin modificar, cargado por sourcing). Sidecar .sha256 de los
# binarios OSU obligatorio en el job (si falta, para y no se genera).
# Jobs: 2 × 2 nodos × 00:30:00 = 2 × 1 = 2,000000 nodo-hora. Con L17 (2,333333): 4,333333 ≤ 5.
# Despliegue solo si hace falta: sha256 de los ficheros en el remoto; si difieren, se despliega
# el HEAD (git archive + rsync, solo commiteado) y se recomprueba.
# Raw: data/raw/lusitania/lat-normales/<par>-<job>/ del checkout de Lusitania (mkdir -p previo
# del directorio de los .out, que Slurm no crea).
# Commit de lat-normales.sbatch: 42c016c5288405bda69d0d1e9693d1eee4b02249.
# EXPECTED_PAIR lleva «+» entre nodos porque Slurm separa --export por comas.
# Tras firma: SIGNED_LAUNCH_SHA=<firma> bash launch/20261017-L18-lusitania-lat-normales.sh
# DRY_RUN=1: comprobaciones simuladas, lat-normales.sbatch en seco (REPO, W y SCRATCH en medida y _rank)
# y 2 envíos secos, sin SSH.
set -euo pipefail
LAUNCH_REL=launch/20261017-L18-lusitania-lat-normales.sh
check_sha() {
    local actual
    actual=$(sha256sum < "$1")
    test "${actual%% *}" = "$2" || { printf 'sha256 MAL: %s\n' "$1" >&2; exit 4; }
    printf 'sha256 OK: %s\n' "$1"
}
if [ "${DRY_RUN:-0}" != 1 ]; then
    : "${SIGNED_LAUNCH_SHA:?falta firma SHA completa}"
    check_sha "$LAUNCH_REL" "$SIGNED_LAUNCH_SHA"
    # shellcheck source=/dev/null
    source clusters/local.env
    : "${LUSITANIA_REPO:?falta LUSITANIA_REPO}"
fi
SHAS=(
    "c279b84b7315fc8c9ad1fe8b11feff047d3f38a94ed1adf9989d31c29dc74eaa  experiments/portable/lat-normales.sbatch"
    "aeee75bafb910678ba7b0fd46b82cd45e682f767aed111d4c20582958992db81  experiments/portable/equiv-us63-v2.sbatch"
    "722752beff83e18098988bbde754dfd5905feb8f93d00f5f70c1555c22fb1d67  experiments/portable/perfil.sh"
    "d7a3c72a19c7cea65a771ad9b02a96141f72ab01a6e3b3472f73c9c18d7d48cf  clusters/perfiles/lusitania-us63.env"
    "24077987874075fd47df1c3f44626265665ad25153da2928a2a2438753767c63  instrumentation/cmdlog.sh"
    "b0754484d7ddc4dc7c7f7e986564bc5c481f9330a06baa977c64f8cb3d96664d  instrumentation/level1_capture.sh"
)
for linea in "${SHAS[@]}"; do check_sha "${linea#*  }" "${linea%%  *}"; done
QOS_U=$( # shellcheck disable=SC1090
    source clusters/perfiles/lusitania-us63.env >/dev/null 2>&1; printf '%s' "$QOS")
UCPUS=$( # shellcheck disable=SC1090
    source clusters/perfiles/lusitania-us63.env >/dev/null 2>&1; printf '%s' "$DECLARED_CORES")
if [ "${UCPUS:-0}" != 16 ]; then printf 'perfil con CPUs inesperadas\n' >&2; exit 3; fi
if [ "${DRY_RUN:-0}" = 1 ]; then
    LUSITANIA_REPO='<lusitania_repo>'   # no se usa en seco
fi
comprobar_remoto() {  # $1: alias; $2: repo
    {
        printf 'cd %q || exit 3\n' "$2"
        printf 'sha256sum -c - <<'"'"'SHA'"'"'\n'
        printf '%s\n' "${SHAS[@]}"
        printf 'SHA\n'
    } | ssh -o BatchMode=yes -o ConnectTimeout=20 "$1" 'bash -se'
}
desplegar() {  # $1: alias; $2: repo — solo ficheros commiteados (regla 9 del arnés).
    local tmp; tmp=$(mktemp -d "${TMPDIR:-/tmp}/l18-deploy.XXXXXX")
    git archive HEAD experiments instrumentation launch clusters/perfiles | tar -xf - -C "$tmp"
    rsync -rq -e 'ssh -o BatchMode=yes -o ConnectTimeout=20' \
        "$tmp/experiments" "$tmp/instrumentation" "$tmp/launch" "$1:$2/"
    rsync -rq -e 'ssh -o BatchMode=yes -o ConnectTimeout=20' "$tmp/clusters/perfiles" "$1:$2/clusters/"
    rm -rf "$tmp"
}
if [ "${DRY_RUN:-0}" = 1 ]; then
    printf 'DRY_RUN remoto: sha256 de los %s ficheros OK (simulado), sin SSH\n' "${#SHAS[@]}"
    DRY_RUN=1 bash experiments/portable/lat-normales.sbatch medida
    DRY_RUN=1 bash experiments/portable/lat-normales.sbatch _rank lat /tmp/dry -m 8:8
    DRY_RUN=1 bash experiments/portable/lat-normales.sbatch _rank bw /tmp/dry -m 4194304:4194304
else
    printf '%s\n' '--- conectividad y sha256 remotos'
    ssh -o BatchMode=yes -o ConnectTimeout=20 computaex 'printf "conexión OK desde "; hostname' \
        || { printf 'sin conexión con Lusitania: se para\n' >&2; exit 3; }
    if ! comprobar_remoto computaex "$LUSITANIA_REPO"; then
        printf 'sha256 remoto distinto en Lusitania: desplegando el HEAD\n'
        desplegar computaex "$LUSITANIA_REPO"
        comprobar_remoto computaex "$LUSITANIA_REPO"
    fi
    printf '%s\n' '--- sha256 remotos OK'
    ssh -o BatchMode=yes -o ConnectTimeout=20 computaex \
        "cd $(printf '%q' "$LUSITANIA_REPO") && mkdir -p data/raw/lusitania/lat-normales"
fi
enviar() {  # $1: variable; resto: argumentos de sbatch.
    local var=$1 id cmd a
    shift
    if [ "${DRY_RUN:-0}" = 1 ]; then
        printf 'DRY_RUN sbatch'; for a in "$@"; do printf ' %q' "$a"; done; printf '\n'
        printf -v "$var" '%s' "${var}_ID"
    else
        cmd="cd $(printf '%q' "$LUSITANIA_REPO") && sbatch"
        for a in "$@"; do cmd+=" $(printf '%q' "$a")"; done
        id=$(ssh -o BatchMode=yes -o ConnectTimeout=20 computaex "$cmd")
        id=${id%%;*}
        [[ "$id" =~ ^[0-9]+$ ]] || { printf 'job ID no válido: %s\n' "$var" >&2; exit 5; }
        printf -v "$var" '%s' "$id"
    fi
    printf '%s=%s\n' "$var" "${!var}"
}
UARGS=(--parsable --exclusive --partition=us63 --nodes=2 --ntasks-per-node=1 "--cpus-per-task=$UCPUS" --time=00:30:00)
if [ -n "$QOS_U" ]; then UARGS+=("--qos=$QOS_U"); fi
enviar P1 "${UARGS[@]}" "--nodelist=s02r1b09,s02r1b17" \
    "--export=ALL,EXPECTED_PAIR=s02r1b09+s02r1b17" \
    "--output=data/raw/lusitania/lat-normales/s02r1b09-s02r1b17-%j.out" experiments/portable/lat-normales.sbatch medida
enviar P2 "${UARGS[@]}" "--nodelist=s02r2b03,s02r2b05" \
    "--export=ALL,EXPECTED_PAIR=s02r2b03+s02r2b05" \
    "--output=data/raw/lusitania/lat-normales/s02r2b03-s02r2b05-%j.out" experiments/portable/lat-normales.sbatch medida
printf 'cadena L18: 2 envíos independientes (2 nodos × 00:30:00 cada uno)\n'
