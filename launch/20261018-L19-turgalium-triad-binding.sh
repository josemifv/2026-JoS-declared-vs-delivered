#!/usr/bin/env bash
# T53 parte C — L19: STREAM (Triad) con hilos fijados frente a la colocación por defecto en
# cuatro nodos de Turgalium cpu36c: aac111 y acc111 (los excluidos por Triad) y, como referencias,
# aac104 (SMT off) y acc102 (SMT on). Orden de la persona (T53 parte C, 2026-10-18): excepción
# expresa al carril C para Turgalium solo en esta parte. NO ENVÍA NADA hasta que la persona
# firme este fichero por su sha256 completo (arnés, regla 3).
# Jobs: 4 exclusivos de 1 nodo × 00:20:00, sin dependencias = 4 × 1/3 = 1,333333 nodo-hora.
# Script: experiments/portable/triad-binding-cpu36c.sbatch (22 rondas, 11 por colocación) con el
# perfil clusters/perfiles/turgalium-cpu36c.env (sin usuario ni rutas; REPO y SCRATCH de local.env).
# Binario de la criba de cpu36c (src/stream/stream_c) SIN sidecar: sha256 fijado aquí y en el
# perfil (opción b de la persona), 89bf0994…744f; no se genera sidecar. Cada ronda exige
# «Array size = 40000000»; si no, el job para. Módulos de la criba: openmpi_gcc/5.0.5 ucx/1.9.0.
# Despliegue solo si hace falta y SOLO de los 3 ficheros necesarios (el checkout de Turgalium es
# del carril A: no se sobrescribe nada más). Solo se despliega lo commiteado.
# Raw: data/raw/turgalium/triad-binding/ del checkout de Turgalium (mkdir -p previo).
# Commit del script y el perfil: e7e64ea43612684ddb55a6005fa020b27b4e00b6.
# Tras firma: SIGNED_LAUNCH_SHA=<firma> bash launch/20261018-L19-turgalium-triad-binding.sh
# DRY_RUN=1: puertas locales, sbatch en seco (REPO, SCRATCH y W) y 4 envíos secos, sin SSH.
set -euo pipefail
LAUNCH_REL=launch/20261018-L19-turgalium-triad-binding.sh
STREAM_SHA=89bf099493eb976407021b8881adfbea3c2b78740e15d0c571c9bd2456b8744f
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
    : "${TURGALIUM_REPO:?falta TURGALIUM_REPO}"
fi
SHAS=(
    "996dc6e50c86565674dd72c4f3eb13fd427407aae0f2de4b5673143018e6bb0e  experiments/portable/triad-binding-cpu36c.sbatch"
    "6f1ba06aefa4151b356c411fd2ed22d819f32aa89761afd07ff3cf40c279621f  clusters/perfiles/turgalium-cpu36c.env"
    "24077987874075fd47df1c3f44626265665ad25153da2928a2a2438753767c63  instrumentation/cmdlog.sh"
)
for linea in "${SHAS[@]}"; do check_sha "${linea#*  }" "${linea%%  *}"; done
# El perfil debe fijar el mismo sha256 de STREAM que este lanzador, 40M y 36 CPUs declaradas.
PERFIL_CHK=$( # shellcheck disable=SC1091
    source clusters/perfiles/turgalium-cpu36c.env >/dev/null 2>&1
    printf '%s|%s|%s|%s' "$STREAM_BIN_SHA256" "$STREAM_ARRAY_SIZE" "$DECLARED_CORES" "$PARTITION")
test "$PERFIL_CHK" = "$STREAM_SHA|40000000|36|cpu36c" || { printf 'perfil inesperado\n' >&2; exit 3; }
CPUS=36
if [ "${DRY_RUN:-0}" = 1 ]; then
    TURGALIUM_REPO='<turgalium_repo>'   # no se usa en seco
fi
comprobar_remoto() {
    {
        printf 'cd %q || exit 3\n' "$TURGALIUM_REPO"
        printf 'sha256sum -c - <<'"'"'SHA'"'"'\n'
        printf '%s\n' "${SHAS[@]}"
        printf 'SHA\n'
    } | ssh -o BatchMode=yes -o ConnectTimeout=20 turgalium 'bash -se'
}
desplegar() {  # solo los 3 ficheros del lanzador, desde HEAD (commiteado)
    local tmp; tmp=$(mktemp -d "${TMPDIR:-/tmp}/l19-deploy.XXXXXX")
    git archive HEAD experiments/portable/triad-binding-cpu36c.sbatch clusters/perfiles/turgalium-cpu36c.env \
        instrumentation/cmdlog.sh | tar -xf - -C "$tmp"
    ( cd "$tmp" && rsync -rq --relative -e 'ssh -o BatchMode=yes -o ConnectTimeout=20' \
        experiments/portable/triad-binding-cpu36c.sbatch clusters/perfiles/turgalium-cpu36c.env \
        instrumentation/cmdlog.sh "turgalium:$TURGALIUM_REPO/" )
    rm -rf "$tmp"
}
if [ "${DRY_RUN:-0}" = 1 ]; then
    printf 'DRY_RUN remoto: sha256 de los %s ficheros OK (simulado), sin SSH\n' "${#SHAS[@]}"
    PERFIL=clusters/perfiles/turgalium-cpu36c.env DRY_RUN=1 bash experiments/portable/triad-binding-cpu36c.sbatch
else
    printf '%s\n' '--- conectividad y sha256 remotos'
    ssh -o BatchMode=yes -o ConnectTimeout=20 turgalium 'printf "conexión OK desde "; hostname' \
        || { printf 'sin conexión con Turgalium: se para\n' >&2; exit 3; }
    if ! comprobar_remoto; then
        printf 'sha256 remoto distinto en Turgalium: desplegando los 3 ficheros del HEAD\n'
        desplegar
        comprobar_remoto
    fi
    printf '%s\n' '--- sha256 remotos OK'
    ssh -o BatchMode=yes -o ConnectTimeout=20 turgalium \
        "cd $(printf '%q' "$TURGALIUM_REPO") && mkdir -p data/raw/turgalium/triad-binding"
fi
enviar() {  # $1: variable; $2: nodo
    local var=$1 nodo=$2 id cmd a
    local args=(--parsable --exclusive --partition=cpu36c --nodes=1 --ntasks=1 "--cpus-per-task=$CPUS"
        --time=00:20:00 "--nodelist=$nodo"
        "--export=ALL,PERFIL=clusters/perfiles/turgalium-cpu36c.env,EXPECTED_NODE=$nodo"
        "--output=data/raw/turgalium/triad-binding/$nodo-%j.out" experiments/portable/triad-binding-cpu36c.sbatch)
    if [ "${DRY_RUN:-0}" = 1 ]; then
        printf 'DRY_RUN sbatch'; for a in "${args[@]}"; do printf ' %q' "$a"; done; printf '\n'
        printf -v "$var" '%s' "${var}_ID"
    else
        cmd="cd $(printf '%q' "$TURGALIUM_REPO") && sbatch"
        for a in "${args[@]}"; do cmd+=" $(printf '%q' "$a")"; done
        id=$(ssh -o BatchMode=yes -o ConnectTimeout=20 turgalium "$cmd")
        id=${id%%;*}
        [[ "$id" =~ ^[0-9]+$ ]] || { printf 'job ID no válido: %s\n' "$var" >&2; exit 5; }
        printf -v "$var" '%s' "$id"
    fi
    printf '%s=%s\n' "$var" "${!var}"
}
enviar T1 aac111
enviar T2 acc111
enviar T3 aac104
enviar T4 acc102
printf 'cadena L19: 4 envíos independientes (1 nodo × 00:20:00 cada uno)\n'
