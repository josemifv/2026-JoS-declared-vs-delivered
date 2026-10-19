#!/usr/bin/env bash
# T50 — L16b: Lusitania us63; compilación (humo), verificación, descubrimiento, equivalencia y calibración.
# Orden: informes/ordenes/2026-10-15-T50-resolucion.md (sha256 b0484fa6…), que resuelve la escalada
# de T50; DEVIATIONS 2026-10-15 us63. L16 se conserva sin firmar y no se lanza.
# Commit de los scripts nuevos: 510448270415bfb399d79349d07541cc22706782; el resto, sin cambios
# desde L16 (commit 3b0e33307611e2b07bbdf5c30a6a22a4b07b4c60). Rigen las puertas sha256 de abajo.
# Cadena, en este orden; cada paso depende con afterok de TODOS los jobs del paso anterior y
# lleva --kill-on-invalid-dep=yes (un fallo elimina lo que queda de la cadena):
#  a. compila-us63.sbatch (OSU, NPB EP/FT C/D, STREAM 40M): 1 nodo × 00:30:00 = 0,5 nodo-h.
#     Hace de humo. 00:30:00 y no 01:00:00 para caber en 20 nodo-h: 753696 (misma compilación
#     sin STREAM, partición lusitania) duró 2:28 (informes/tareas/T49/L15b-S07.txt).
#  b. verif.sbatch: 2 nodos × 01:00:00 = 2 nodo-h, como en L16.
#  c. descubrimiento: run_discovery.sh (sin --submit; solo escribe un job por nodo) y una línea
#     sbatch por nodo: 12 jobs × 1 nodo × 00:20:00 (fijado por run_discovery.sh) = 4 nodo-h.
#  d. equiv-us63.sbatch medida: 11 pares REF+nodo × 2 nodos × 00:20:00 = 7,333333 nodo-h.
#  e. calib.sbatch: 8 nodos × 00:45:00 = 6 nodo-h, como en L16.
# Total: 26 jobs, 19,833333 nodo-h reservadas <= 20 (orden, paso 5). Con 12 nodos en la
# equivalencia (mínimo de la orden) y 12 descubiertos no cabe ninguno más: 13 darían 20,166667.
# Nodos (us63 en T50/C2: s02r1b01-42 con 31000 MiB y s02r2b01-10 con 62000 MiB, 16 CPU):
#  descubrimiento = 6 nodos equiespaciados por clase de memoria en el orden de sinfo, extremos
#  incluidos: s02r1b01 s02r1b09 s02r1b17 s02r1b26 s02r1b34 s02r1b42 (31000 MiB) y
#  s02r2b01 s02r2b03 s02r2b05 s02r2b06 s02r2b08 s02r2b10 (62000 MiB).
#  equivalencia = los mismos 12: referencia s02r1b01 (primer nodo de la clase mayoritaria) con
#  cada uno de los otros 11, en ese orden. verif y calib, sin lista de nodos, como en L16.
# Runs: a) 8 NPB + 2 instalaciones OSU + 1 STREAM; b) una fila por transporte enumerado
# (dinámico); c) 12 JSON; d) 11 × 44 = 484 (242 STREAM + 121 lat + 121 bw; ronda 1 de calentamiento
# en cada job, 10 efectivas); e) 4 (2 pilas × FT C/D, 128 ranks).
# Duración: tope de la ruta crítica 0,5 + 1 + 0,33 + 11 × 0,33 (pares en serie por la referencia)
# + 0,75 = 6 h 15 min de ejecución como máximo, más la cola.
# Raw: stdout de los 26 jobs, descubrimiento y equivalencia en cc/raw/lusitania/us63/ del scratch;
# compila/verif/calib escriben además su directorio <nombre>-<job> en cc/raw/lusitania/fase1/
# (lo fija init_job de perfil.sh, que no se modifica). Sync --ignore-existing a data/raw/lusitania/.
# Requisito previo: $SCRATCH/src/stream/stream.c con SHA256 a52bae5e…; si falta, para sin enviar.
# Tras la firma: SIGNED_LAUNCH_SHA=<firma> bash launch/20261015-L16b-lusitania-us63.sh
# DRY_RUN=1: solo puertas locales, run_discovery.sh en un temporal y 26 envíos secos; sin SSH.
set -euo pipefail
LAUNCH_REL=launch/20261015-L16b-lusitania-us63.sh
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
check_sha experiments/portable/compila-us63.sbatch ce19ba76118e520608eca47c4dd873810f258b825599976151407d2c75170432
check_sha experiments/portable/verif.sbatch a98d055c71db738797a813130b27b18c1822bd7d8bc92f70fbc048a637b23136
check_sha experiments/portable/calib.sbatch 10737a3fcae7ab1f63b2759b39a9247b502bb5cade85fd91be3e41c82fab19d0
check_sha experiments/portable/pin.sh 0874457ed4d699a897af9d292c489b353f99fab028d9f5402f35b8524cc7b355
check_sha experiments/portable/observa.py 79826bb6d3ff9cbe2997d310b55865ddf0c0986cb947906ad09e4baff9945f40
check_sha experiments/portable/equiv-us63.sbatch a1dcfecfa5832e1e734d40112546eedd9ed4ab5186fdf04e9854951c7ac19e18
check_sha discovery/run_discovery.sh a461371c0d4c6fe112a02c0d354a44fd4eea00429c848700b0ce9dc4920be2e0
check_sha discovery/collect_node.py 2c743b218d8ccbd6dd7789de6b48391c4176462f16776ab2608e5ebe4477b345
check_sha discovery/fingerprint.py c1198e22e43e5f9dab34a14873586ae6c04f54d7d18d959e586eb70eddf7f79c
check_sha instrumentation/cmdlog.sh 24077987874075fd47df1c3f44626265665ad25153da2928a2a2438753767c63
check_sha instrumentation/level1_capture.sh b0754484d7ddc4dc7c7f7e986564bc5c481f9330a06baa977c64f8cb3d96664d
export PERFIL=clusters/perfiles/lusitania-us63.env
# shellcheck source=/dev/null
source experiments/portable/perfil.sh
test "$PARTITION" = us63 && test "$CALIB_RPN" = 16 && test "$CALIB_NODES" = 8 || { printf 'perfil distinto del previsto\n' >&2; exit 3; }
U="$SCRATCH/cc/raw/lusitania/us63"
DISC_LIST=s02r1b01,s02r1b09,s02r1b17,s02r1b26,s02r1b34,s02r1b42,s02r2b01,s02r2b03,s02r2b05,s02r2b06,s02r2b08,s02r2b10
ACCOUNT_ARGS=(); DISCOVERY_ACCOUNT=()
if [ -n "$ACCOUNT" ]; then
    ACCOUNT_ARGS=("--account=$ACCOUNT"); DISCOVERY_ACCOUNT=(--account "$ACCOUNT")
fi
if [ "${DRY_RUN:-0}" = 1 ]; then
    DISC_DIR=$(mktemp -d "${TMPDIR:-/tmp}/l16b-disc.XXXXXX")
    trap 'rm -rf "$DISC_DIR"' EXIT
else
    DISC_DIR="$U/discovery"
    "$PYTHON_DISCOVERY" -c 'import sys; assert sys.version_info >= (3, 7)'
    actual=$(sha256sum < "$SCRATCH/src/stream/stream.c") || { printf 'falta fuente STREAM\n' >&2; exit 3; }
    test "${actual%% *}" = a52bae5e175bea3f7832112af9c085adab47117f7d2ce219165379849231692b \
        || { printf 'fuente STREAM distinta\n' >&2; exit 3; }
    test ! -e "$U" || { printf 'ya existe %s: no se mezcla con un lanzamiento anterior\n' "$U" >&2; exit 3; }
    mkdir -p "$U/equivalence" "$DISC_DIR"
    CMDLOG_DIR="$U" CMDLOG_RUN_ID=l16b-inventario bash "$W" sinfo -h -N -p us63 -o '%N %c %m' > "$U/inventario.txt"
    # 52 nodos declarados; los 12 elegidos, con 16 CPU y en las dos clases de memoria.
    awk -v lista="$DISC_LIST" 'BEGIN {n = split(lista, w, ","); for (i = 1; i <= n; i++) want[w[i]] = 1}
        !seen[$1]++ {total++; if ($1 in want) {if ($2 != 16) bad = 1; found++; mem[$3] = 1}}
        END {c = 0; for (m in mem) c++; exit !(total == 52 && found == n && !bad && c == 2)}' "$U/inventario.txt" \
        || { printf 'inventario de us63 distinto del esperado\n' >&2; exit 3; }
fi
SB=(--parsable --exclusive --partition=us63 "--chdir=$REPO" ${ACCOUNT_ARGS[@]+"${ACCOUNT_ARGS[@]}"})
EXP="--export=ALL,PERFIL=$PERFIL"
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
# Un error detiene los envíos que faltan sin cancelar nada.
# a. Compilación (humo).
enviar COMPILA "${SB[@]}" "$EXP" --nodes=1 --ntasks=1 --time=00:30:00 "--output=$U/compila-%j.out" experiments/portable/compila-us63.sbatch
# b. Verificación a 2 nodos.
enviar VERIF "${SB[@]}" "$EXP" --nodes=2 --ntasks=32 --ntasks-per-node=16 --time=01:00:00 "--dependency=afterok:$COMPILA" --kill-on-invalid-dep=yes "--output=$U/verif-%j.out" experiments/portable/verif.sbatch
# c. Descubrimiento: run_discovery.sh sin --submit escribe un job por nodo; se envían aquí.
bash discovery/run_discovery.sh --cluster lusitania --partition us63 --nodes "$DISC_LIST" --repo "$REPO" \
    --data-dir "$DISC_DIR" --jobs-dir "$DISC_DIR/jobs" --wrapper "$W" --python "$PYTHON_DISCOVERY" \
    ${DISCOVERY_ACCOUNT[@]+"${DISCOVERY_ACCOUNT[@]}"} > "$DISC_DIR/genera.log" 2>&1
test "$(grep -c '^\[dry-run\] sbatch' "$DISC_DIR/genera.log")" = 12
grep -q '^dry-run: no se ha enviado ningun job' "$DISC_DIR/genera.log"
for node in ${DISC_LIST//,/ }; do
    grep -qx "#SBATCH --nodelist=$node" "$DISC_DIR/jobs/disc_$node.sbatch"
    grep -qx '#SBATCH --partition=us63' "$DISC_DIR/jobs/disc_$node.sbatch"
    grep -qx '#SBATCH --time=00:20:00' "$DISC_DIR/jobs/disc_$node.sbatch"
done
printf 'descubrimiento: 12 jobs generados por run_discovery.sh, sin envío propio\n'
DD=(--parsable "--chdir=$REPO" "--dependency=afterok:$VERIF" --kill-on-invalid-dep=yes)
enviar DISC01 "${DD[@]}" "$DISC_DIR/jobs/disc_s02r1b01.sbatch"
enviar DISC02 "${DD[@]}" "$DISC_DIR/jobs/disc_s02r1b09.sbatch"
enviar DISC03 "${DD[@]}" "$DISC_DIR/jobs/disc_s02r1b17.sbatch"
enviar DISC04 "${DD[@]}" "$DISC_DIR/jobs/disc_s02r1b26.sbatch"
enviar DISC05 "${DD[@]}" "$DISC_DIR/jobs/disc_s02r1b34.sbatch"
enviar DISC06 "${DD[@]}" "$DISC_DIR/jobs/disc_s02r1b42.sbatch"
enviar DISC07 "${DD[@]}" "$DISC_DIR/jobs/disc_s02r2b01.sbatch"
enviar DISC08 "${DD[@]}" "$DISC_DIR/jobs/disc_s02r2b03.sbatch"
enviar DISC09 "${DD[@]}" "$DISC_DIR/jobs/disc_s02r2b05.sbatch"
enviar DISC10 "${DD[@]}" "$DISC_DIR/jobs/disc_s02r2b06.sbatch"
enviar DISC11 "${DD[@]}" "$DISC_DIR/jobs/disc_s02r2b08.sbatch"
enviar DISC12 "${DD[@]}" "$DISC_DIR/jobs/disc_s02r2b10.sbatch"
# d. Equivalencia por pares fijos frente a s02r1b01.
EQ=("${SB[@]}" "--export=ALL,PERFIL=$PERFIL,EQUIV_COMPILE_JOB=$COMPILA" --nodes=2 --ntasks-per-node=1 --cpus-per-task=16 --time=00:20:00
    "--dependency=afterok:$DISC01:$DISC02:$DISC03:$DISC04:$DISC05:$DISC06:$DISC07:$DISC08:$DISC09:$DISC10:$DISC11:$DISC12"
    --kill-on-invalid-dep=yes "--output=$U/equivalence/medida-%j.out")
enviar EQ01 "${EQ[@]}" --nodelist=s02r1b01,s02r1b09 experiments/portable/equiv-us63.sbatch medida
enviar EQ02 "${EQ[@]}" --nodelist=s02r1b01,s02r1b17 experiments/portable/equiv-us63.sbatch medida
enviar EQ03 "${EQ[@]}" --nodelist=s02r1b01,s02r1b26 experiments/portable/equiv-us63.sbatch medida
enviar EQ04 "${EQ[@]}" --nodelist=s02r1b01,s02r1b34 experiments/portable/equiv-us63.sbatch medida
enviar EQ05 "${EQ[@]}" --nodelist=s02r1b01,s02r1b42 experiments/portable/equiv-us63.sbatch medida
enviar EQ06 "${EQ[@]}" --nodelist=s02r1b01,s02r2b01 experiments/portable/equiv-us63.sbatch medida
enviar EQ07 "${EQ[@]}" --nodelist=s02r1b01,s02r2b03 experiments/portable/equiv-us63.sbatch medida
enviar EQ08 "${EQ[@]}" --nodelist=s02r1b01,s02r2b05 experiments/portable/equiv-us63.sbatch medida
enviar EQ09 "${EQ[@]}" --nodelist=s02r1b01,s02r2b06 experiments/portable/equiv-us63.sbatch medida
enviar EQ10 "${EQ[@]}" --nodelist=s02r1b01,s02r2b08 experiments/portable/equiv-us63.sbatch medida
enviar EQ11 "${EQ[@]}" --nodelist=s02r1b01,s02r2b10 experiments/portable/equiv-us63.sbatch medida
# e. Calibración a 8 nodos, como en L16.
enviar CALIB "${SB[@]}" "$EXP" --nodes=8 --ntasks=128 --ntasks-per-node=16 --time=00:45:00 "--dependency=afterok:$EQ01:$EQ02:$EQ03:$EQ04:$EQ05:$EQ06:$EQ07:$EQ08:$EQ09:$EQ10:$EQ11" --kill-on-invalid-dep=yes "--output=$U/calib-%j.out" experiments/portable/calib.sbatch
printf 'cadena L16b: 26 envíos\n'
