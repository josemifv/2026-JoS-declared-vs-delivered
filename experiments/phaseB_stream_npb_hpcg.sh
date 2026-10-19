#!/usr/bin/env bash
# OBSOLETO, NO USAR: sustituido por experiments/fase_b.sh (2026-10-04)
# Fase B: matriz cpu112c. Reglas: R1, R8 (clase), R13 (recortes), R10 (afinidad).
# Una invocación por celda: sbatch phaseB_stream_npb_hpcg.sh <stack> <transporte> <bench> <nodos>
#   bench: stream | ep | ft | cg | mg | hpcg
#   nodos: 1 (solo stream y, salvo R13.5, NPB) | 2 | 4 | 8 — 64 ranks/nodo
# PLACEHOLDERS: <<<PARTITION>>> <<<NODELIST>>> <<<BINDING_MAP>>> <<<MODULES_...>>> <<<BENCH_PATHS>>>
#SBATCH --job-name=cc-phaseB
#SBATCH --exclusive
#SBATCH --partition=<<<PARTITION>>>
#SBATCH --nodes=1
#SBATCH --output=data/raw/phaseB/%x-%j.out
#SBATCH --time=04:00:00

set -euo pipefail
source clusters/local.env
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/phaseB/$SLURM_JOB_ID"
export CMDLOG_RUN_ID="B-$SLURM_JOB_ID"
export LEVEL1_MODE="${LEVEL1_MODE:?fijar LEVEL1_MODE (R14): privileged|unprivileged|auto}"

STACK="$1"; TRANSPORT="$2"; BENCH="$3"; NODES="$4"
case "$STACK" in
  gcc)    module load ${MODULES_GCC_OMPI:?definir MODULES_GCC_OMPI en local.env} ;;
  oneapi) module load ${MODULES_ONEAPI_IMPI:?definir MODULES_ONEAPI_IMPI en local.env} ;;
  *) echo "stack desconocido: $STACK" >&2; exit 2 ;;
esac

level1_capture.sh start
level1_capture.sh pre
# 10 repeticiones por celda (R13: NPB/HPCG pueden quedar en 5); primer run = calentamiento (R1).
# STREAM: 1 nodo. NPB: clase fijada en calibración (R8). HPCG: mismos pares que NPB.
# Registra SIEMPRE mapa pedido vs real para la etiqueta de coincidencia (R10).
# <<<BUCLE DE REPETICIONES>>>: srun/mpirun <<<BINDING_MAP>>> ... via cmdlog.sh
level1_capture.sh post
level1_capture.sh stop
