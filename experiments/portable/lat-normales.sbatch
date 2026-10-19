#!/usr/bin/env bash
# T53 L18: latencia y ancho de banda entre nodos NORMALES de us63, sin el nodo de
# referencia de la criba (s02r1b01); responde a las objeciones Codex 3 y Opus M3/M6.
# Orden v3: informes/ordenes/2026-10-17-T53-triad-binding-v3.md. Sin lanzar hasta la firma.
# Por trabajo: 11 rondas de osu_latency con SOLO mensajes de 8 B (-m 8:8) y 11 de osu_bw
# con SOLO 4 MiB (-m 4194304:4194304); la primera de cada prueba es calentamiento; NO se
# cambian las iteraciones ni el calentamiento internos de OSU. Binarios, módulos,
# variables y comprobación de transporte (check_result) EXACTAMENTE los de la criba de
# us63: se reutilizan por sourcing con el guard de equiv-us63-v2.sbatch, sin modificarlo.
# Los sidecars .sha256 de los binarios OSU se comprueban y son OBLIGATORIOS (si faltan,
# el job para y no se genera por cuenta del agente).
# Todo comando pasa por el wrapper cmdlog.sh; nivel 1 como en la criba (_rank equivalente).
# DRY_RUN=1: comprueba REPO, W y SCRATCH (también en _rank) y sale, sin módulos ni Slurm.
# Raw: data/raw/lusitania/lat-normales/<par>-<job>/ del checkout de Lusitania (orden T53 v2/v3).
#SBATCH --exclusive
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --time=00:30:00
set -euo pipefail
MODE=${1:-}
case "$MODE" in
    medida|_rank) ;;
    *) printf 'uso: lat-normales.sbatch medida | lat-normales.sbatch _rank <bench> <dir> [args OSU…]\n' >&2; exit 2 ;;
esac
if [ "${DRY_RUN:-0}" = 1 ]; then
    cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")/../..}"
else
    cd "${SLURM_SUBMIT_DIR:?falta raíz de envío}"
fi
# Perfil de us63 (define REPO, SCRATCH, W, módulos); también en los ranks, como equiv-us63-v2.
export PERFIL=clusters/perfiles/lusitania-us63.env
# shellcheck source=/dev/null
source experiments/portable/perfil.sh
# Ruta del propio sbatch en el checkout de Lusitania (el de Slurm es una copia del spool).
SELF="$REPO/experiments/portable/lat-normales.sbatch"
EQUIV="$REPO/experiments/portable/equiv-us63-v2.sbatch"
BASE="$SCRATCH/cc/raw/lusitania/us63/discovery"
RB="$REPO/data/raw/lusitania/lat-normales"
if [ "${DRY_RUN:-0}" = 1 ]; then
    for v in REPO W SCRATCH SELF EQUIV BASE RB; do
        test -n "${!v:-}" || { printf 'DRY_RUN: %s vacía en modo %s\n' "$v" "$MODE" >&2; exit 3; }
    done
    printf 'lat-normales modo=%s REPO=%s W=%s SCRATCH=%s SELF=%s GNU=%s pruebas=lat(-m 8:8),bw(-m 4194304:4194304) rondas=11\n' \
        "$MODE" "$REPO" "$W" "$SCRATCH" "$SELF" "${GNU_MODULES[*]}"
    exit 0
fi
: "${SLURM_JOB_ID:?solo dentro de Slurm}"
load_stack gnu

_rank() {  # $1: bench (lat|bw); $2: dir del run; $3+: argumentos extra para el binario OSU
    local bench=$1 out=$2 node rank executable libs linked libdir l1
    shift 2
    node=$(hostname -s)
    rank=${OMPI_COMM_WORLD_RANK:-0}
    export CMDLOG_DIR="$out/$node-rank-$rank" CMDLOG_RUN_ID="latn-$SLURM_JOB_ID-$node-$rank"
    mkdir -p "$CMDLOG_DIR"
    export LEVEL1_RUN_ID="$CMDLOG_RUN_ID" LEVEL1_NODE="$node" LEVEL1_CLUSTER=lusitania
    export CONTEXT_DIR="$CMDLOG_DIR/context" LEVEL1_STATE_DIR="$CMDLOG_DIR/state"
    export DISCOVERY_DIR="$CMDLOG_DIR/discovery" LEVEL1_MODE=unprivileged LEVEL1_JOB_LOG="$out/run.log"
    mkdir -p "$DISCOVERY_DIR/lusitania"
    cp "$BASE/$node.json" "$DISCOVERY_DIR/lusitania/$node.json"
    export UCX_LOG_LEVEL=info OMPI_MCA_pml_base_verbose=10 OMPI_MCA_btl_base_verbose=10
    case "$bench" in
        lat) executable="$SCRATCH/benchmarks/osu/gnu/us63/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_latency" ;;
        bw) executable="$SCRATCH/benchmarks/osu/gnu/us63/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bw" ;;
        *) printf 'prueba no prevista: %s\n' "$bench" >&2; exit 2 ;;
    esac
    test -x "$executable"
    # Sidecar obligatorio del binario OSU (política de la orden; NO se genera aquí).
    test -s "$executable.sha256" || { printf 'FALTA SIDECAR: %s.sha256; parando (no se genera)\n' "$executable" >&2; exit 3; }
    local expected actual
    expected=$(cat "$executable.sha256")
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || { printf 'sidecar con formato inesperado\n' >&2; exit 3; }
    actual=$(sha256sum < "$executable")
    test "${actual%% *}" = "$expected" || { printf 'sha256 del binario OSU distinto del sidecar\n' >&2; exit 3; }
    libs=$(bash "$W" ldd "$executable")
    printf '%s\n' "$libs"
    if grep -q 'not found' <<< "$libs"; then printf 'biblioteca no encontrada\n' >&2; exit 3; fi
    linked=$(awk '$1 ~ /^libmpi\.so/ && $2 == "=>" {print $3}' <<< "$libs")
    test -n "$linked"
    libdir=$(ompi_info --parsable --path libdir)
    libdir=${libdir#path:libdir:}
    test "$(dirname "$(readlink -f "$linked")")" = "$(readlink -f "$libdir")"
    test "$(dirname "$(readlink -f "$(command -v mpirun)")")" = \
        "$(dirname "$(readlink -f "$(command -v ompi_info)")")"
    printf 'EQUIV_LIB host=%s rank=%s ok=yes\n' "$node" "$rank"
    l1="$REPO/instrumentation/level1_capture.sh"
    bash "$l1" start
    trap 'ec=$?; trap - EXIT; bash "$l1" post || ec=1; bash "$l1" stop || ec=1; exit "$ec"' EXIT
    bash "$l1" pre
    # El shell hijo pasa a ser el benchmark por exec: misma afinidad y PID; -m del final.
    bash "$W" bash -c 'rank=${OMPI_COMM_WORLD_RANK:-0}; printf "EQUIV_MAP host=%s rank=%s cpus=%s\n" "$(hostname -s)" "$rank" "$(taskset -pc $$ | awk "{print \$NF}")" > "$2/map-$rank.txt"; exec "$1" "${@:3}"' _ "$executable" "$out" "$@"
    exit 0
}

if [ "$MODE" = _rank ]; then
    _rank "${@:2}"
    exit 0
fi
# --- modo medida: una sola vez por job (los ranks vuelven a entrar por _rank) ---
: "${EXPECTED_PAIR:?falta el par esperado (nodoA+nodoB)}" "${SLURM_JOB_ID:?}" "${SLURM_CPUS_PER_TASK:?}"
# check_result de la criba de us63, sin modificar el fichero (el guard de sourcing lo permite).
# shellcheck source=/dev/null disable=SC1091
source "$EQUIV"
node=$(hostname -s)
CMDLOG_DIR="$RB/${EXPECTED_PAIR//+/-}-$SLURM_JOB_ID"
test ! -e "$CMDLOG_DIR" || { printf 'ya existe %s: no se mezcla con un trabajo anterior\n' "$CMDLOG_DIR" >&2; exit 3; }
export CMDLOG_DIR CMDLOG_RUN_ID="latn-$SLURM_JOB_ID" LEVEL1_MODE=unprivileged
mkdir -p "$CMDLOG_DIR"
# Nodos reales de la asignación (sin scontrol), como en la criba.
bash "$W" srun -N 2 -n 2 --ntasks-per-node=1 hostname -s > "$CMDLOG_DIR/nodes-srun.txt"
sort -u "$CMDLOG_DIR/nodes-srun.txt" > "$CMDLOG_DIR/nodes.txt"
NODES=()
while IFS= read -r n; do NODES+=("$n"); done < "$CMDLOG_DIR/nodes.txt"
test "${#NODES[@]}" = 2 && test "${NODES[0]}" != "${NODES[1]}" || exit 5
test "$(printf '%s\n' "${NODES[@]}" | sort | tr '\n' ',')" = "$(printf '%s\n' "$EXPECTED_PAIR" | tr '+' '\n' | sort | tr '\n' ',')" \
    || { printf 'asignación distinta del par esperado: %s\n' "${NODES[*]}" >&2; exit 3; }
manifest="$CMDLOG_DIR/manifest.csv"
printf 'prueba,ronda,warmup,exit_code,verificacion,transporte\n' > "$manifest"
for bench in lat bw; do
    case "$bench" in
        lat) margs=(-m 8:8) ;;
        bw) margs=(-m 4194304:4194304) ;;
    esac
    for rep in $(seq 1 11); do
        warm=0; if [ "$rep" = 1 ]; then warm=1; fi
        rd="$CMDLOG_DIR/$bench-$rep"; mkdir "$rd"
        ec=0
        bash "$W" mpirun -np 2 --map-by ppr:1:node --host "${NODES[0]},${NODES[1]}" \
            bash "$SELF" _rank "$bench" "$rd" "${margs[@]}" > "$rd/run.log" 2>&1 || ec=$?
        verdict=OK
        check_result "$bench" "$rd/run.log" 1 "${NODES[@]}" > "$rd/check.txt" 2>&1 || verdict=FALLO
        transporte=$(sed -n 's/^OK transport=//p' "$rd/check.txt")
        printf '%s,%s,%s,%s,%s,%s\n' "$bench" "$rep" "$warm" "$ec" "$verdict" "${transporte:-sin-observar}" >> "$manifest"
        printf '%s ronda %s: exit=%s %s transporte=%s\n' "$bench" "$rep" "$ec" "$verdict" "${transporte:-sin-observar}"
        test "$verdict" = OK || { printf '%s ronda %s FALLO: se detiene el job\n' "$bench" "$rep" >&2; exit 5; }
    done
done
printf 'OK: 22 rondas (11 lat -m 8:8, 11 bw -m 4194304:4194304) entre %s y %s\n' "${NODES[0]}" "${NODES[1]}"
