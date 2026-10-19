#!/usr/bin/env bash
# Fase A: OSU por par stack-transporte. Reglas: R2 (selección), R13 (recorte 10→5).
# Una invocación por celda: sbatch phaseA_osu.sh <stack> <transporte> <prueba> <nodos>
#   stack:     gcc | oneapi
#   transporte: p. ej. rc|dc|ud|tcp (UCX) o proveedor libfabric
#   prueba:    latency | bw | bibw | allreduce | alltoall
#   nodos:     2 (pt2pt) | 8 (colectivas), 64 ranks/nodo
# PLACEHOLDERS: <<<PARTITION>>> <<<NODELIST>>> <<<BINDING_MAP>>> <<<MODULES_...>>> <<<OSU_PATH>>> (por pila: benchmarks/osu/<pila>)
#SBATCH --job-name=cc-phaseA
#SBATCH --exclusive
#SBATCH --partition=<<<PARTITION>>>
#SBATCH --nodes=1
#SBATCH --output=data/raw/phaseA/%x-%j.out
#SBATCH --time=02:00:00

set -euo pipefail
source clusters/local.env
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/phaseA/$SLURM_JOB_ID"
export CMDLOG_RUN_ID="A-$SLURM_JOB_ID"
export LEVEL1_MODE="${LEVEL1_MODE:?fijar LEVEL1_MODE (R14): privileged|unprivileged|auto}"

STACK="$1"; TRANSPORT="$2"; TEST="$3"; NODES="$4"
case "$STACK" in
  gcc)    module load ${MODULES_GCC_OMPI:?definir MODULES_GCC_OMPI en local.env} ;;
  oneapi) module load ${MODULES_ONEAPI_IMPI:?definir MODULES_ONEAPI_IMPI en local.env} ;;
  *) echo "stack desconocido: $STACK" >&2; exit 2 ;;
esac

# Transporte solicitado por stack (UCX_* / FI_PROVIDER); el EFECTIVO lo fija el nivel 1.
# <<<EXPORTS_DE_TRANSPORTE>>>

level1_capture.sh start
level1_capture.sh pre
# 10 repeticiones (R13 puede dejarlas en 5); 1 rank/nodo en pt2pt a 2 nodos,
# 64 ranks/nodo en colectivas; binding explícito, un rank por core físico.
# <<<BUCLE DE REPETICIONES>>>: lanzador POR PILA sobre el build OSU de la pila
# (DEVIATIONS 2026-10-02, requisito para TODO lanzador OSU): gcc -> mpirun -np N
# --map-by ppr:K:node --bind-to core; intel/oneapi -> mpirun -n N -ppn K (Hydra ignora
# -map-by y reparte mal). El mapa pedido y el real quedan en nivel 1 (R10).
# <<<BUCLE_DE_REPETICIONES>>>: run_mpi_por_pila <<<BINDING_MAP>>> $OSU_PATH/OSU_$TEST ... via cmdlog.sh
level1_capture.sh post
level1_capture.sh stop
