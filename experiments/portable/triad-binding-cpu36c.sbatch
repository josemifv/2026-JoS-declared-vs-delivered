#!/usr/bin/env bash
# T53 parte C (L19): STREAM (Triad) con la lógica de triad-binding.sbatch en un nodo de cpu36c de
# Turgalium: 22 rondas alternando A (un hilo por CPU declarada por Slurm, sin binding, como la
# criba) y B (un hilo por core físico de lscpu, OMP_PLACES=cores, OMP_PROC_BIND=spread);
# 11 ejecuciones por colocación; calentamiento: ronda 1 de A y ronda 2 de B.
# Orden de la persona (T53 parte C, 2026-10-18). Autorización expresa al carril C para
# Turgalium solo en esta parte. Sin lanzar hasta la firma.
# Binario de la criba de cpu36c (src/stream/stream_c): SIN sidecar; se comprueba contra el sha256
# fijado en el perfil (STREAM_BIN_SHA256, decisión (b) de la persona); no se genera sidecar.
# Cada ronda exige «Array size = 40000000» en la salida de STREAM; si no, el job para.
# Variante de triad-binding.sbatch porque perfil.sh (firmado) solo admite XULA|LUSITANIA.
# Raw: data/raw/turgalium/triad-binding/<nodo>-<job>/ del checkout de Turgalium.
#SBATCH --exclusive
#SBATCH --nodes=1
#SBATCH --partition=cpu36c
#SBATCH --ntasks=1
#SBATCH --time=00:20:00
set -euo pipefail
if [ "${DRY_RUN:-0}" = 1 ]; then
    cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")/../..}"
else
    cd "${SLURM_SUBMIT_DIR:?falta raíz de envío}"
fi
: "${PERFIL:?falta PERFIL}"
# shellcheck source=/dev/null
source "$PERFIL"
# shellcheck source=/dev/null
source clusters/local.env
: "${TURGALIUM_REPO:?falta TURGALIUM_REPO}" "${TURGALIUM_SCRATCH:?falta TURGALIUM_SCRATCH}"
REPO=$TURGALIUM_REPO; SCRATCH=$TURGALIUM_SCRATCH
W="$REPO/instrumentation/cmdlog.sh"
if [ "${DRY_RUN:-0}" = 1 ]; then   # antes de los módulos (no existen fuera del clúster); sin imprimir rutas privadas
    for v in REPO SCRATCH W; do test -n "${!v:-}" || { printf 'DRY_RUN: %s vacía\n' "$v" >&2; exit 3; }; done
    printf 'triad-binding-cpu36c DRY_RUN: REPO, SCRATCH y W definidas; módulos=%s binario=%s sha256=%s array=%s\n' \
        "${GNU_MODULES[*]}" "$STREAM_BIN_REL" "$STREAM_BIN_SHA256" "$STREAM_ARRAY_SIZE"
    exit 0
fi
test -f "$W" || { printf 'falta cmdlog\n' >&2; exit 3; }
module purge 2>/dev/null || true
module load "${GNU_MODULES[@]}"
: "${EXPECTED_NODE:?falta nodo esperado}" "${SLURM_JOB_ID:?}" "${SLURM_CPUS_PER_TASK:?falta cpus-per-task}"
node=$(hostname -s)
test "$node" = "$EXPECTED_NODE" || { printf 'nodo distinto del pedido: %s (esperado %s)\n' "$node" "$EXPECTED_NODE" >&2; exit 3; }
RB="$REPO/data/raw/$CLUSTER/triad-binding"  # CLUSTER=turgalium (perfil)
CMDLOG_DIR="$RB/$node-$SLURM_JOB_ID"
test ! -e "$CMDLOG_DIR" || { printf 'ya existe %s: no se mezcla con un trabajo anterior\n' "$CMDLOG_DIR" >&2; exit 3; }
export CMDLOG_DIR CMDLOG_RUN_ID="triad-$SLURM_JOB_ID" LEVEL1_MODE=unprivileged
mkdir -p "$CMDLOG_DIR"
# Binario de la criba de cpu36c: sha256 fijado en el perfil (sin sidecar; no se genera).
bin="$SCRATCH/$STREAM_BIN_REL"
test -x "$bin" || { printf 'falta el binario STREAM\n' >&2; exit 3; }
[[ "$STREAM_BIN_SHA256" =~ ^[0-9a-f]{64}$ ]] || { printf 'sha256 del perfil con formato inesperado\n' >&2; exit 3; }
actual=$(sha256sum < "$bin")
test "${actual%% *}" = "$STREAM_BIN_SHA256" || { printf 'sha256 del binario distinto del fijado en el perfil\n' >&2; exit 3; }
printf 'binario STREAM (%s): %s OK frente al sha256 del perfil\n' "$STREAM_BIN_REL" "${actual%% *}"
# Registro del nodo: lscpu (esencial: da los cores físicos de B) y numactl -H (si falta, se registra y sigue).
bash "$W" lscpu > "$CMDLOG_DIR/lscpu.txt"
bash "$W" numactl -H > "$CMDLOG_DIR/numactl.txt" || printf 'numactl no disponible en %s\n' "$node" >&2
cores=$(lscpu -p=CPU,CORE | grep -v '^#' | cut -d, -f2 | sort -nu | wc -l)
test "$cores" -ge 1 || { printf 'lscpu no dio cores físicos\n' >&2; exit 3; }
printf 'cores físicos (lscpu): %s; CPUs declaradas por Slurm: %s\n' "$cores" "$SLURM_CPUS_PER_TASK"
# 22 rondas alternando A (impar) y B (par); calentamiento: ronda 1 de A y ronda 2 de B.
manifest="$CMDLOG_DIR/manifest.csv"
printf 'ronda,colocacion,warmup,threads,exit_code,verificacion,triad_MBps\n' > "$manifest"
for r in $(seq 1 22); do
    if [ $((r % 2)) -eq 1 ]; then
        col=A; threads="$SLURM_CPUS_PER_TASK"; warm=0
        if [ "$r" = 1 ]; then warm=1; fi
        unset OMP_PLACES OMP_PROC_BIND   # A: colocación por defecto, sin binding (como la criba)
    else
        col=B; threads="$cores"; warm=0
        if [ "$r" = 2 ]; then warm=1; fi
        export OMP_PLACES=cores OMP_PROC_BIND=spread
    fi
    export OMP_NUM_THREADS="$threads" OMP_DISPLAY_AFFINITY=TRUE OMP_AFFINITY_FORMAT='thread=%n cpus=%A'
    rd="$CMDLOG_DIR/r$(printf '%02d' "$r")-$col"; mkdir "$rd"
    ec=0
    bash "$W" "$bin" > "$rd/run.log" 2>&1 || ec=$?
    verificacion=OK; triad=$(grep -E '^Triad:' "$rd/run.log" | head -1 | awk '{print $2}' || true)
    nthr=$(grep -cE '^thread=[0-9]+ cpus=' "$rd/run.log" || true)
    grep -qE "^Array size = $STREAM_ARRAY_SIZE \(elements\)" "$rd/run.log" || verificacion=FALLO
    { [ -n "$triad" ] && [ "$nthr" = "$threads" ] && [ "$ec" = 0 ]; } || verificacion=FALLO
    printf '%s,%s,%s,%s,%s,%s,%s\n' "$r" "$col" "$warm" "$threads" "$ec" "$verificacion" "${triad:--}" >> "$manifest"
    printf 'ronda %s %s: triad=%s threads=%s exit=%s %s\n' "$r" "$col" "${triad:--}" "$nthr" "$ec" "$verificacion"
    test "$verificacion" = OK || { printf 'ronda %s %s FALLO: se detiene el job\n' "$r" "$col" >&2; exit 5; }
done
printf 'OK: 22 rondas (A: 11 con %s hilos, B: 11 con %s hilos físicos)\n' "$SLURM_CPUS_PER_TASK" "$cores"
