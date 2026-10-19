#!/usr/bin/env bash
# T53 L17: STREAM (Triad) en un nodo señalado por la criba, 22 rondas alternando dos
# colocaciones (11 ejecuciones por colocación), para las objeciones M5 (Opus) y Codex 3:
# A = como la criba (un hilo por CPU declarada por Slurm, sin variables de binding);
# B = un hilo por core físico (OMP_NUM_THREADS = cores de lscpu en el nodo,
# OMP_PLACES=cores, OMP_PROC_BIND=spread).
# La primera ronda de cada colocación es calentamiento (A: ronda 1; B: ronda 2).
# V3 (orden informes/ordenes/2026-10-17-T53-triad-binding-v3.md): 22 rondas (antes 11)
# y control de us63 s02r2b03 en lugar de s02r1b09.
# Orden: informes/ordenes/2026-10-17-T53-triad-binding.md. Sin lanzar hasta la firma.
# Binario y módulo de la criba de cada clúster (sin recompilar); el sidecar .sha256 del
# binario es OBLIGATORIO: si falta, el job para y no se genera por cuenta del agente.
# Raw: data/raw/<cluster>/triad-binding/<nodo>-<job>/ del checkout del clúster (orden T53).
# Todo comando pasa por el wrapper cmdlog.sh (registro, hash de salida, código de salida).
#SBATCH --exclusive
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:20:00
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:?falta raíz de envío}"
: "${PERFIL:?falta PERFIL}"
# shellcheck source=/dev/null
source experiments/portable/perfil.sh
load_stack gnu
: "${EXPECTED_NODE:?falta nodo esperado}" "${SLURM_JOB_ID:?}" "${SLURM_CPUS_PER_TASK:?falta cpus-per-task}"
node=$(hostname -s)
test "$node" = "$EXPECTED_NODE" || { printf 'nodo distinto del pedido: %s (esperado %s)\n' "$node" "$EXPECTED_NODE" >&2; exit 3; }
RB="$REPO/data/raw/$CLUSTER/triad-binding"
CMDLOG_DIR="$RB/$node-$SLURM_JOB_ID"
test ! -e "$CMDLOG_DIR" || { printf 'ya existe %s: no se mezcla con un trabajo anterior\n' "$CMDLOG_DIR" >&2; exit 3; }
export CMDLOG_DIR CMDLOG_RUN_ID="triad-$SLURM_JOB_ID" LEVEL1_MODE=unprivileged
mkdir -p "$CMDLOG_DIR"
# Binario de la criba de cada clúster (T49: stream_spr en xula4; T50: stream_40M en us63).
case "$ENV_PREFIX" in
    XULA) bin="$SCRATCH/benchmarks/stream/gnu/$PARTITION/stream_spr" ;;
    LUSITANIA) bin="$SCRATCH/benchmarks/stream/gnu/$PARTITION/stream_40M" ;;
    *) printf 'clúster no previsto: %s\n' "$ENV_PREFIX" >&2; exit 2 ;;
esac
# Sidecar obligatorio: si falta, parar y avisar; NO se genera por cuenta del agente.
test -s "$bin.sha256" || { printf 'FALTA SIDECAR: %s.sha256; parando (no se genera)\n' "$bin" >&2; exit 3; }
expected=$(cat "$bin.sha256")
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || { printf 'sidecar con formato inesperado: %s.sha256\n' "$bin" >&2; exit 3; }
actual=$(sha256sum < "$bin")
test "${actual%% *}" = "$expected" || { printf 'sha256 del binario distinto del sidecar: %s\n' "$bin" >&2; exit 3; }
printf 'binario %s: %s OK\n' "$bin" "${actual%% *}"
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
    { [ -n "$triad" ] && [ "$nthr" = "$threads" ] && [ "$ec" = 0 ]; } || verificacion=FALLO
    printf '%s,%s,%s,%s,%s,%s,%s\n' "$r" "$col" "$warm" "$threads" "$ec" "$verificacion" "${triad:--}" >> "$manifest"
    printf 'ronda %s %s: triad=%s threads=%s exit=%s %s\n' "$r" "$col" "${triad:--}" "$nthr" "$ec" "$verificacion"
    test "$verificacion" = OK || { printf 'ronda %s %s FALLO: se detiene el job\n' "$r" "$col" >&2; exit 5; }
done
printf 'OK: 22 rondas (A: 11 con %s hilos, B: 11 con %s hilos físicos)\n' "$SLURM_CPUS_PER_TASK" "$cores"
