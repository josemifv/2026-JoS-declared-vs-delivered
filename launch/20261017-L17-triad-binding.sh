#!/usr/bin/env bash
# T53 — L17: STREAM (Triad) con hilos fijados frente a la colocación por defecto, en los
# nodos señalados por la criba; responde a la objeción M5 del revisor Opus.
# Orden: informes/ordenes/2026-10-17-T53-triad-binding.md. NO ENVÍA NADA hasta que la
# persona firme este fichero por su sha256 completo (arnés, regla 3).
# Nodos (justificación en TASKS.md/T53):
#   Xula xula4: xula5204 (SMT), xula5304, xula5401 y xula5504 (referencia de la criba L15b/T49).
#   Lusitania us63: s02r2b01 (SMT: threads_per_core=2 en el descubrimiento de L16b; Triad ≈27 GB/s),
#     s02r1b01 (referencia de la criba, ≈44,9 GB/s frente a 56-60 del resto) y s02r2b03 (control, ≈59 GB/s).
# Jobs: 7 exclusivos de 1 nodo × 00:20:00 = 7 × 1/3 = 2,333333 nodo-hora ≤ 3 (orden).
# En Xula, como mucho 2 a la vez (límite de la cuenta): J3 afterok:J1 y J4 afterok:J2, con
# kill-on-invalid-dep. En us63: 3 envíos independientes.
# Binario de la criba de cada clúster, con sidecar .sha256 OBLIGATORIO (si falta, el job
# para y no se genera por cuenta del agente): xula4 → stream_spr (T49); us63 → stream_40M (T50).
# Módulo: pila gnu de cada perfil. Raw: data/raw/<cluster>/triad-binding/ del checkout del clúster.
# Despliegue solo si hace falta: sha256 de los 5 ficheros en el remoto; si difieren, se
# despliega el HEAD (git archive + rsync, solo commiteado) y se recomprueba.
# V3 (orden informes/ordenes/2026-10-17-T53-triad-binding-v3.md): 22 rondas (11 por colocación) y
# control de us63 s02r2b03 (antes s02r1b09); presupuesto total de la tarea 4,333333 nodo-hora ≤ 5.
# Commit de triad-binding.sbatch: 63de165d (v3, introducido con la orden v3).
# Los directorios de salida (--output) se crean con mkdir -p remoto antes de los envíos.
# Tras nueva firma: SIGNED_LAUNCH_SHA=<firma> bash launch/20261017-L17-triad-binding.sh
# DRY_RUN=1: 7 envíos secos y comprobaciones simuladas, sin SSH.
set -euo pipefail
LAUNCH_REL=launch/20261017-L17-triad-binding.sh
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
    : "${XULA_REPO:?falta XULA_REPO}" "${LUSITANIA_REPO:?falta LUSITANIA_REPO}"
fi
check_sha experiments/portable/triad-binding.sbatch 7734b2a86920f705be71305e47a4b839bb7b6e3438e913e7cc7517546d348301
check_sha experiments/portable/perfil.sh 722752beff83e18098988bbde754dfd5905feb8f93d00f5f70c1555c22fb1d67
check_sha clusters/perfiles/xula4.env 07324486a8be1bcc4aeaf12e8e60924ed7518751b36e551620aba2a47e6ef99e
check_sha clusters/perfiles/lusitania-us63.env d7a3c72a19c7cea65a771ad9b02a96141f72ab01a6e3b3472f73c9c18d7d48cf
check_sha instrumentation/cmdlog.sh 24077987874075fd47df1c3f44626265665ad25153da2928a2a2438753767c63
# QoS y CPUs declaradas de cada perfil.
lee_perfil() {  # $1: fichero; imprime "QOS|DECLARED_CORES" (el | evita el stripping del read con QOS vacío)
    ( # shellcheck disable=SC1090
      source "clusters/perfiles/$1.env" >/dev/null 2>&1; printf '%s|%s' "$QOS" "$DECLARED_CORES" )
}
IFS='|' read -r XQOS XCPUS <<< "$(lee_perfil xula4)"
IFS='|' read -r UQOS UCPUS <<< "$(lee_perfil lusitania-us63)"
if [ "${XCPUS:-0}" != 112 ] || [ "${UCPUS:-0}" != 16 ]; then
    printf 'perfiles con CPUs inesperadas\n' >&2; exit 3
fi
if [ "${DRY_RUN:-0}" = 1 ]; then
    XULA_REPO='<xula_repo>' LUSITANIA_REPO='<lusitania_repo>'   # no se usan en seco
fi
# Comprobación remota de sha256; si difiere, despliegue del HEAD y recomprobación.
comprobar_remoto() {  # $1: alias; $2: repo
    {
        printf 'cd %q || exit 3\n' "$2"
        printf 'sha256sum -c - <<'"'"'SHA'"'"'\n'
        printf '7734b2a86920f705be71305e47a4b839bb7b6e3438e913e7cc7517546d348301  experiments/portable/triad-binding.sbatch\n'
        printf '722752beff83e18098988bbde754dfd5905feb8f93d00f5f70c1555c22fb1d67  experiments/portable/perfil.sh\n'
        printf '07324486a8be1bcc4aeaf12e8e60924ed7518751b36e551620aba2a47e6ef99e  clusters/perfiles/xula4.env\n'
        printf 'd7a3c72a19c7cea65a771ad9b02a96141f72ab01a6e3b3472f73c9c18d7d48cf  clusters/perfiles/lusitania-us63.env\n'
        printf '24077987874075fd47df1c3f44626265665ad25153da2928a2a2438753767c63  instrumentation/cmdlog.sh\n'
        printf 'SHA\n'
    } | ssh -o BatchMode=yes -o ConnectTimeout=20 "$1" 'bash -se'
}
desplegar() {  # $1: alias; $2: repo — solo ficheros commiteados (regla 9 del arnés).
    local tmp; tmp=$(mktemp -d "${TMPDIR:-/tmp}/l17-deploy.XXXXXX")
    git archive HEAD experiments instrumentation launch clusters/perfiles | tar -xf - -C "$tmp"
    rsync -rq -e 'ssh -o BatchMode=yes -o ConnectTimeout=20' \
        "$tmp/experiments" "$tmp/instrumentation" "$tmp/launch" "$1:$2/"
    rsync -rq -e 'ssh -o BatchMode=yes -o ConnectTimeout=20' "$tmp/clusters/perfiles" "$1:$2/clusters/"
    rm -rf "$tmp"
}
if [ "${DRY_RUN:-0}" = 1 ]; then
    printf 'DRY_RUN remoto: sha256 de los 5 ficheros OK (simulado), sin SSH\n'
else
    printf '%s\n' '--- conectividad y sha256 remotos (Xula requiere VPN del CIEMAT)'
    ssh -o BatchMode=yes -o ConnectTimeout=20 xula 'printf "conexión OK desde "; hostname' \
        || { printf 'sin conexión con Xula (¿VPN del CIEMAT?): se para\n' >&2; exit 3; }
    if ! comprobar_remoto xula "$XULA_REPO"; then
        printf 'sha256 remoto distinto en Xula: desplegando el HEAD\n'
        desplegar xula "$XULA_REPO"
        comprobar_remoto xula "$XULA_REPO"
    fi
    if ! comprobar_remoto computaex "$LUSITANIA_REPO"; then
        printf 'sha256 remoto distinto en Lusitania: desplegando el HEAD\n'
        desplegar computaex "$LUSITANIA_REPO"
        comprobar_remoto computaex "$LUSITANIA_REPO"
    fi
    printf '%s\n' '--- sha256 remotos OK en ambos clústeres'
fi
# Slurm no crea el directorio de --output: se crea (mkdir -p, sin tocar nada existente) antes de enviar.
preparar_salida() {  # $1: alias; $2: repo; $3: directorio relativo
    if [ "${DRY_RUN:-0}" = 1 ]; then
        printf 'DRY_RUN mkdir -p %s (remoto, sin SSH)\n' "$3"
    else
        ssh -o BatchMode=yes -o ConnectTimeout=20 "$1" "cd $(printf '%q' "$2") && mkdir -p $(printf '%q' "$3")"
    fi
}
preparar_salida xula "$XULA_REPO" data/raw/xula/triad-binding
preparar_salida computaex "$LUSITANIA_REPO" data/raw/lusitania/triad-binding
enviar() {  # $1: variable; $2: alias; $3: repo; resto: argumentos de sbatch.
    local var=$1 alias=$2 repo=$3 id cmd a
    shift 3
    if [ "${DRY_RUN:-0}" = 1 ]; then
        printf 'DRY_RUN sbatch'; for a in "$@"; do printf ' %q' "$a"; done; printf '\n'
        printf -v "$var" '%s' "${var}_ID"
    else
        cmd="cd $(printf '%q' "$repo") && sbatch"
        for a in "$@"; do cmd+=" $(printf '%q' "$a")"; done
        id=$(ssh -o BatchMode=yes -o ConnectTimeout=20 "$alias" "$cmd")
        id=${id%%;*}
        [[ "$id" =~ ^[0-9]+$ ]] || { printf 'job ID no válido: %s\n' "$var" >&2; exit 5; }
        printf -v "$var" '%s' "$id"
    fi
    printf '%s=%s\n' "$var" "${!var}"
}
# Argumentos comunes por clúster.
XARGS=(--parsable --exclusive --partition=xula4 --nodes=1 --ntasks=1 "--cpus-per-task=$XCPUS" --time=00:20:00)
UARGS=(--parsable --exclusive --partition=us63 --nodes=1 --ntasks=1 "--cpus-per-task=$UCPUS" --time=00:20:00)
if [ -n "$XQOS" ]; then XARGS+=("--qos=$XQOS"); fi
if [ -n "$UQOS" ]; then UARGS+=("--qos=$UQOS"); fi
# Xula: J1 y J2 sin dependencia; J3 y J4 afterok con kill-on-invalid-dep (máximo 2 a la vez).
enviar J1 xula "$XULA_REPO" "${XARGS[@]}" "--nodelist=xula5204" \
    "--export=ALL,PERFIL=clusters/perfiles/xula4.env,EXPECTED_NODE=xula5204" \
    "--output=data/raw/xula/triad-binding/xula5204-%j.out" experiments/portable/triad-binding.sbatch
enviar J2 xula "$XULA_REPO" "${XARGS[@]}" "--nodelist=xula5304" \
    "--export=ALL,PERFIL=clusters/perfiles/xula4.env,EXPECTED_NODE=xula5304" \
    "--output=data/raw/xula/triad-binding/xula5304-%j.out" experiments/portable/triad-binding.sbatch
enviar J3 xula "$XULA_REPO" "${XARGS[@]}" "--dependency=afterok:$J1" --kill-on-invalid-dep=yes "--nodelist=xula5401" \
    "--export=ALL,PERFIL=clusters/perfiles/xula4.env,EXPECTED_NODE=xula5401" \
    "--output=data/raw/xula/triad-binding/xula5401-%j.out" experiments/portable/triad-binding.sbatch
enviar J4 xula "$XULA_REPO" "${XARGS[@]}" "--dependency=afterok:$J2" --kill-on-invalid-dep=yes "--nodelist=xula5504" \
    "--export=ALL,PERFIL=clusters/perfiles/xula4.env,EXPECTED_NODE=xula5504" \
    "--output=data/raw/xula/triad-binding/xula5504-%j.out" experiments/portable/triad-binding.sbatch
# Lusitania us63: los 3 en paralelo, sin dependencias.
enviar U1 computaex "$LUSITANIA_REPO" "${UARGS[@]}" "--nodelist=s02r2b01" \
    "--export=ALL,PERFIL=clusters/perfiles/lusitania-us63.env,EXPECTED_NODE=s02r2b01" \
    "--output=data/raw/lusitania/triad-binding/s02r2b01-%j.out" experiments/portable/triad-binding.sbatch
enviar U2 computaex "$LUSITANIA_REPO" "${UARGS[@]}" "--nodelist=s02r1b01" \
    "--export=ALL,PERFIL=clusters/perfiles/lusitania-us63.env,EXPECTED_NODE=s02r1b01" \
    "--output=data/raw/lusitania/triad-binding/s02r1b01-%j.out" experiments/portable/triad-binding.sbatch
enviar U3 computaex "$LUSITANIA_REPO" "${UARGS[@]}" "--nodelist=s02r2b03" \
    "--export=ALL,PERFIL=clusters/perfiles/lusitania-us63.env,EXPECTED_NODE=s02r2b03" \
    "--output=data/raw/lusitania/triad-binding/s02r2b03-%j.out" experiments/portable/triad-binding.sbatch
printf 'cadena L17: 7 envíos (Xula: J3 afterok:J1 y J4 afterok:J2; us63: en paralelo)\n'
