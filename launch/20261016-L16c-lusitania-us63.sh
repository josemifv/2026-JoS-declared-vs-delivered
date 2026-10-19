#!/usr/bin/env bash
# T51 — L16c: Lusitania us63; equivalencia (comprobación corregida) y calibración.
# Orden: informes/ordenes/2026-10-16-T51-us63-completar.md (sha256 7a76bdc3…) y aclaración
# informes/ordenes/2026-10-16-T51-aclaracion.md (la comprobación registra el transporte
# observado; en us63 es ucx:rc_verbs). Deriva de launch/20261015-L16b-lusitania-us63.sh:
# sin compila, verif ni descubrimiento. Usa los binarios que L16b (753860) ya compiló:
# su existencia y sha256 se comprueban antes del envío, sin recompilar. La base de huellas
# es el descubrimiento de L16b (cc/raw/lusitania/us63/discovery), solo lectura.
# Los 11 pares y su orden son los de L16b, todos frente a la referencia s02r1b01, para que
# la comparación con L16b sea directa. EQ01 hace de humo; EQ02-EQ11 dependen de EQ01 con
# afterok y --kill-on-invalid-dep=yes; calib.sbatch (8 nodos × 00:45:00) depende SOLO de
# EQ01, para que el fallo de un par posterior no la cancele.
# Presupuesto: 11 × 2 × 20/60 + 8 × 45/60 = 7,333333 + 6 = 13,333333 nodo-h ≤ 15 (orden, paso 5).
# Duración estimada: ~6,5 min por par en serie (la referencia s02r1b01 los serializa) más la
# calibración en paralelo desde EQ01: ~1 h 15 min de ejecución, más la cola.
# Raw: cc/raw/lusitania/us63-l16c/ (nuevo); los datos de L16b no se mezclan.
# Commit de equiv-us63-v2.sbatch: 759dc77e2f7b3e8fb603772d950914bced6f6e1a; no lanzar sin firma.
# Tras nueva firma: SIGNED_LAUNCH_SHA=<firma> bash launch/20261016-L16c-lusitania-us63.sh
# DRY_RUN=1: solo puertas locales y 12 envíos secos, sin SSH.
set -euo pipefail
LAUNCH_REL=launch/20261016-L16c-lusitania-us63.sh
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
        # shellcheck source=/dev/null
        source clusters/local.env
        : "${LUSITANIA_REPO:?falta LUSITANIA_REPO}"
        EXPECTED_DEPLOY_COMMIT=$(git rev-parse HEAD)
        { printf 'cd %q\nexport PORTABLE_REMOTE=1\nexport EXPECTED_DEPLOY_COMMIT=%q\nexport SIGNED_LAUNCH_SHA=%q\n' \
            "$LUSITANIA_REPO" "$EXPECTED_DEPLOY_COMMIT" "$SIGNED_LAUNCH_SHA"; cat "$LAUNCH_FILE"; } | ssh computaex 'bash -s'
        exit "$?"
    fi
fi
if [ "${DRY_RUN:-0}" != 1 ]; then
    : "${SIGNED_LAUNCH_SHA:?falta firma SHA completa}" "${EXPECTED_DEPLOY_COMMIT:?falta commit desplegado}"
    check_sha "$LAUNCH_REL" "$SIGNED_LAUNCH_SHA"
    test "$(cat .deploy-commit)" = "$EXPECTED_DEPLOY_COMMIT"
    printf 'deploy OK: %s\n' "$EXPECTED_DEPLOY_COMMIT"
fi
check_sha clusters/perfiles/lusitania-us63.env d7a3c72a19c7cea65a771ad9b02a96141f72ab01a6e3b3472f73c9c18d7d48cf
check_sha experiments/portable/perfil.sh 722752beff83e18098988bbde754dfd5905feb8f93d00f5f70c1555c22fb1d67
check_sha experiments/portable/equiv-us63-v2.sbatch aeee75bafb910678ba7b0fd46b82cd45e682f767aed111d4c20582958992db81
check_sha experiments/portable/calib.sbatch 10737a3fcae7ab1f63b2759b39a9247b502bb5cade85fd91be3e41c82fab19d0
check_sha instrumentation/cmdlog.sh 24077987874075fd47df1c3f44626265665ad25153da2928a2a2438753767c63
check_sha instrumentation/level1_capture.sh b0754484d7ddc4dc7c7f7e986564bc5c481f9330a06baa977c64f8cb3d96664d
export PERFIL=clusters/perfiles/lusitania-us63.env
# shellcheck source=/dev/null
source experiments/portable/perfil.sh
test "$PARTITION" = us63 && test "$CALIB_RPN" = 16 && test "$CALIB_NODES" = 8 || { printf 'perfil distinto del previsto\n' >&2; exit 3; }
U="$SCRATCH/cc/raw/lusitania/us63-l16c"
BASE="$SCRATCH/cc/raw/lusitania/us63/discovery"
ACCOUNT_ARGS=()
if [ -n "$ACCOUNT" ]; then
    ACCOUNT_ARGS=("--account=$ACCOUNT")
fi
if [ "${DRY_RUN:-0}" != 1 ]; then
    "$PYTHON_DISCOVERY" -c 'import sys; assert sys.version_info >= (3, 7)'
    for bin in "$SCRATCH/benchmarks/stream/gnu/us63/stream_40M" \
        "$SCRATCH/benchmarks/osu/gnu/us63/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_latency" \
        "$SCRATCH/benchmarks/osu/gnu/us63/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bw"; do
        test -x "$bin" && test -s "$bin.sha256" || { printf 'falta binario de L16b: %s\n' "$bin" >&2; exit 3; }
        printf 'binario %s: ' "$bin"
        sha256sum < "$bin"
    done
    test -f "$BASE/s02r1b01.json" || { printf 'falta la base de huellas de L16b\n' >&2; exit 3; }
    test ! -e "$U" || { printf 'ya existe %s: no se mezcla con un lanzamiento anterior\n' "$U" >&2; exit 3; }
    mkdir -p "$U/equivalence"
fi
SB=(--parsable --exclusive --partition=us63 "--chdir=$REPO" ${ACCOUNT_ARGS[@]+"${ACCOUNT_ARGS[@]}"})
EQ=("${SB[@]}" "--export=ALL,PERFIL=$PERFIL,EQUIV_COMPILE_JOB=753860" --nodes=2 --ntasks-per-node=1 --cpus-per-task=16 --time=00:20:00
    --kill-on-invalid-dep=yes "--output=$U/equivalence/medida-%j.out")
enviar() {
    # $1: variable que recibe el job ID; el resto son los argumentos de sbatch.
    local var=$1 id
    shift
    if [ "${DRY_RUN:-0}" = 1 ]; then
        printf 'DRY_RUN sbatch'; printf ' %q' "$@"; printf '\n'
        id="${var}_ID"
    else
        id=$(sbatch "$@")
        id=${id%%;*}
        [[ "$id" =~ ^[0-9]+$ ]] || { printf 'job ID no válido: %s\n' "$var" >&2; exit 5; }
    fi
    printf '%s=%s\n' "$var" "$id"
    printf -v "$var" '%s' "$id"
}
# EQ01 hace de humo; el resto de pares y la calibración dependen de él.
enviar EQ01 "${EQ[@]}" --nodelist=s02r1b01,s02r1b09 experiments/portable/equiv-us63-v2.sbatch medida
enviar EQ02 "${EQ[@]}" --dependency=afterok:$EQ01 --kill-on-invalid-dep=yes --nodelist=s02r1b01,s02r1b17 experiments/portable/equiv-us63-v2.sbatch medida
enviar EQ03 "${EQ[@]}" --dependency=afterok:$EQ01 --kill-on-invalid-dep=yes --nodelist=s02r1b01,s02r1b26 experiments/portable/equiv-us63-v2.sbatch medida
enviar EQ04 "${EQ[@]}" --dependency=afterok:$EQ01 --kill-on-invalid-dep=yes --nodelist=s02r1b01,s02r1b34 experiments/portable/equiv-us63-v2.sbatch medida
enviar EQ05 "${EQ[@]}" --dependency=afterok:$EQ01 --kill-on-invalid-dep=yes --nodelist=s02r1b01,s02r1b42 experiments/portable/equiv-us63-v2.sbatch medida
enviar EQ06 "${EQ[@]}" --dependency=afterok:$EQ01 --kill-on-invalid-dep=yes --nodelist=s02r1b01,s02r2b01 experiments/portable/equiv-us63-v2.sbatch medida
enviar EQ07 "${EQ[@]}" --dependency=afterok:$EQ01 --kill-on-invalid-dep=yes --nodelist=s02r1b01,s02r2b03 experiments/portable/equiv-us63-v2.sbatch medida
enviar EQ08 "${EQ[@]}" --dependency=afterok:$EQ01 --kill-on-invalid-dep=yes --nodelist=s02r1b01,s02r2b05 experiments/portable/equiv-us63-v2.sbatch medida
enviar EQ09 "${EQ[@]}" --dependency=afterok:$EQ01 --kill-on-invalid-dep=yes --nodelist=s02r1b01,s02r2b06 experiments/portable/equiv-us63-v2.sbatch medida
enviar EQ10 "${EQ[@]}" --dependency=afterok:$EQ01 --kill-on-invalid-dep=yes --nodelist=s02r1b01,s02r2b08 experiments/portable/equiv-us63-v2.sbatch medida
enviar EQ11 "${EQ[@]}" --dependency=afterok:$EQ01 --kill-on-invalid-dep=yes --nodelist=s02r1b01,s02r2b10 experiments/portable/equiv-us63-v2.sbatch medida
enviar CALIB "${SB[@]}" "--export=ALL,PERFIL=$PERFIL" --nodes=8 --ntasks=128 --ntasks-per-node=16 --time=00:45:00 --dependency=afterok:$EQ01 --kill-on-invalid-dep=yes "--output=$U/calib-%j.out" experiments/portable/calib.sbatch
printf 'cadena L16c: 12 envíos\n'
