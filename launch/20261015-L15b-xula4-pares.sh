#!/usr/bin/env bash
# T49 — L15b: pares fijos GNU 40M contra referencia xula5504.
# Autoriza: informes/ordenes/2026-10-15-T49-L15b.md y aclaración;
# DEVIATIONS 2026-10-15 L15b, entradas T49 2026-10-14, R1/R14.
# Commit de equiv-v2.sbatch: 8d821c391aafb43b6d66dce937ff523fdbc11cc8.
# V1 y L15 firmados intactos; esta preparación requiere nueva firma completa.
# 20 jobs de 2 nodos exclusivos, 112 CPUs/tarea, 1 tarea/nodo, QoS a.
# Todos 00:20:00: 20 × 2 × 20/60 = 13,333333 nodo-hora reservadas.
# Primero humo xula5504,xula5003: 1 ronda, 4 runs (2 STREAM + lat + bw).
# No recompila: binario/sidecar comparados con SHA del humo 2736189.
# Otros 19 pares: 11 rondas, 44 runs/job (22 STREAM + 11 lat + 11 bw).
# Primera ronda calentamiento; total 840 runs (420 STREAM + 210 lat + 210 bw).
# El primer par solo tiene humo, sin 10 rondas efectivas; no añadir otro job.
# Orden: xula5003 xula5004 xula5101 xula5102 xula5103 xula5104 xula5201
# xula5203 xula5204 xula5301 xula5302 xula5303 xula5304 xula5401 xula5402
# xula5501 xula5502 xula5503 xula5602 xula5604, siempre junto a xula5504.
# Exclusiones: xula5001,xula5002,xula5202,xula5403,xula5404,xula5603.
# Las 19 medidas afterok del primero y kill-on-invalid-dep=yes.
# QA a-d dentro del humo de la misma forma; f exceptuado, g sync, h firma/puertas.
# Corte: sábado 17 octubre 12:00; nodos no medidos se declaran no cubiertos.
# Desplegar también los 22 JSON de data/raw/xula/fase1/discovery.
# Raw: cc/raw/xula/equivalence/{humo,medida}-JOBID; stdout en checkout
# data/raw/xula/equivalence/. Sync --ignore-existing, sin analizar.
# Tras nueva firma: SIGNED_LAUNCH_SHA=<firma> bash launch/20261015-L15b-xula4-pares.sh
# DRY_RUN=1: solo puertas locales y 20 envíos secos, sin SSH ni sbatch real.
set -euo pipefail
LAUNCH_REL=launch/20261015-L15b-xula4-pares.sh
check_sha() {
    local actual
    actual=$(sha256sum < "$1")
    test "${actual%% *}" = "$2" || { printf 'sha256 MAL: %s\n' "$1" >&2; exit 4; }
    printf 'sha256 OK: %s\n' "$1"
}
if [ "${PORTABLE_REMOTE:-0}" != 1 ]; then
    LAUNCH_FILE="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    cd "$(dirname "$LAUNCH_FILE")/.."
    if [ "${DRY_RUN:-0}" != 1 ]; then
        : "${SIGNED_LAUNCH_SHA:?falta firma SHA completa}"
        check_sha "$LAUNCH_REL" "$SIGNED_LAUNCH_SHA"
        source clusters/local.env
        : "${XULA_REPO:?}"
        EXPECTED_DEPLOY_COMMIT=$(git rev-parse HEAD)
        { printf 'cd %q\nexport PORTABLE_REMOTE=1\nexport EXPECTED_DEPLOY_COMMIT=%q\nexport SIGNED_LAUNCH_SHA=%q\n' \
            "$XULA_REPO" "$EXPECTED_DEPLOY_COMMIT" "$SIGNED_LAUNCH_SHA"; cat "$LAUNCH_FILE"; } | ssh xula 'bash -s'
        exit "$?"
    fi
fi
if [ "${DRY_RUN:-0}" != 1 ]; then
    : "${SIGNED_LAUNCH_SHA:?falta firma SHA completa}" "${EXPECTED_DEPLOY_COMMIT:?falta commit desplegado}"
    check_sha "$LAUNCH_REL" "$SIGNED_LAUNCH_SHA"
    test "$(cat .deploy-commit)" = "$EXPECTED_DEPLOY_COMMIT"
    printf 'deploy OK: %s\n' "$EXPECTED_DEPLOY_COMMIT"
fi
check_sha experiments/portable/equiv-v2.sbatch 0b51fc60fa544f8c5bb945ead4a1719a63d03090b337dbfb2785c8295a57a884
check_sha experiments/portable/perfil.sh 722752beff83e18098988bbde754dfd5905feb8f93d00f5f70c1555c22fb1d67
check_sha clusters/perfiles/xula4.env 07324486a8be1bcc4aeaf12e8e60924ed7518751b36e551620aba2a47e6ef99e
check_sha discovery/collect_node.py 2c743b218d8ccbd6dd7789de6b48391c4176462f16776ab2608e5ebe4477b345
check_sha discovery/fingerprint.py c1198e22e43e5f9dab34a14873586ae6c04f54d7d18d959e586eb70eddf7f79c
check_sha instrumentation/cmdlog.sh 24077987874075fd47df1c3f44626265665ad25153da2928a2a2438753767c63
check_sha instrumentation/level1_capture.sh b0754484d7ddc4dc7c7f7e986564bc5c481f9330a06baa977c64f8cb3d96664d
export PERFIL=clusters/perfiles/xula4.env
# shellcheck source=/dev/null
source experiments/portable/perfil.sh
PYTHON=python3
[ "${DRY_RUN:-0}" = 1 ] || PYTHON=$PYTHON_DISCOVERY
"$PYTHON" -I -c '
import hashlib
from pathlib import Path
ps = sorted(Path("data/raw/xula/fase1/discovery").glob("*.json"))
assert len(ps) == 22
actual = hashlib.sha256("".join(p.name + ":" + hashlib.sha256(p.read_bytes()).hexdigest() + "\n" for p in ps).encode()).hexdigest()
assert actual == "a1adce082881af0e133430388f6ae1dcc1315dcb16f623329c657e7fd75a1761", "JSON de referencia distintos"
print("sha256 OK: 22 JSON de descubrimiento")
'
EXCLUDE=xula5001,xula5002,xula5202,xula5403,xula5404,xula5603
COMMON=(--parsable --exclusive --partition=xula4 --qos=a --nodes=2
    --ntasks-per-node=1 --cpus-per-task=112 --time=00:20:00 "--exclude=$EXCLUDE")
[ -z "$ACCOUNT" ] || COMMON+=("--account=$ACCOUNT")
if [ "${DRY_RUN:-0}" = 1 ]; then
    dry_sbatch() { printf 'DRY_RUN sbatch'; printf ' %q' "$@"; printf '\n'; }
    # El identificador es solo marcador; no se ejecuta sbatch.
    dry_sbatch "${COMMON[@]}" --nodelist=xula5504,xula5003 --output=data/raw/xula/equivalence/humo-%j.out experiments/portable/equiv-v2.sbatch humo
    HUMO=900000
else
    mkdir -p data/raw/xula/equivalence
    HUMO=$(sbatch "${COMMON[@]}" --nodelist=xula5504,xula5003 --output=data/raw/xula/equivalence/humo-%j.out experiments/portable/equiv-v2.sbatch humo)
    HUMO=${HUMO%%;*}
    [[ "$HUMO" =~ ^[0-9]+$ ]] || exit 5
    printf 'humo=%s\n' "$HUMO"
fi
COMMON+=("--dependency=afterok:$HUMO" --kill-on-invalid-dep=yes "--export=ALL,EQUIV_SMOKE_JOB=$HUMO" --output=data/raw/xula/equivalence/medida-%j.out)
SEND=(sbatch)
[ "${DRY_RUN:-0}" != 1 ] || SEND=(dry_sbatch)
# Una línea por medida, en el orden firmado. Un error detiene envíos sin cancelar.
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5004 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5101 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5102 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5103 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5104 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5201 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5203 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5204 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5301 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5302 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5303 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5304 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5401 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5402 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5501 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5502 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5503 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5602 experiments/portable/equiv-v2.sbatch medida
"${SEND[@]}" "${COMMON[@]}" --nodelist=xula5504,xula5604 experiments/portable/equiv-v2.sbatch medida
