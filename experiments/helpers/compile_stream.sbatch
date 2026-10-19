#!/usr/bin/env bash
#SBATCH --job-name=compile-stream
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --account=<account>
#SBATCH --time=00:10:00
#SBATCH --output=data/raw/phaseB/compile-stream-%j.out
# STREAM (OpenMP, fuente única en scratch/src/stream/stream.c) compilado por pila
# para la matriz de fase B: -fopenmp -O3 -march=sapphirerapids. STREAM no usa red:
# la comparación entre pilas es compilador + librería de hilos. Los 64 hilos se
# pinean en fase_b.sh al mismo mapa explícito que los ranks MPI
# (GOMP_CPU_AFFINITY / KMP_AFFINITY, mapa 0-31,56-87). §8: falla si falta la fuente.
set -euo pipefail
# Bajo sbatch, $0 es la copia en /var/lib/slurmd (fallo del job 83292): cd al
# directorio de envío (raíz del checkout), no a dirname $0.
cd "${SLURM_SUBMIT_DIR:-$PWD}"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env
W="$PWD/instrumentation/cmdlog.sh"
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/phaseB/compile-stream-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="compile-stream-$SLURM_JOB_ID"
mkdir -p "$CMDLOG_DIR"
SRC="$TURGALIUM_SCRATCH/src/stream/stream.c"
[ -f "$SRC" ] || { echo "!! fuente no encontrada: $SRC" >&2; exit 1; }
build() { # $1 = pila; $2 = módulos
  echo "== STREAM $1 (sapphirerapids)"
  module purge 2>/dev/null || true; module load $2
  local d="$TURGALIUM_SCRATCH/benchmarks/stream/$1"
  mkdir -p "$d"
  bash "$W" mpicc -fopenmp -O3 -march=sapphirerapids "$SRC" -o "$d/stream_spr" -lm 2>&1 | tail -2
  if [ -x "$d/stream_spr" ]; then echo "   ok: $d/stream_spr"; else echo "   !! no generado ($1)" >&2; exit 4; fi
}
build gcc "openmpi_gcc/5.0.5 ucx/1.9.0"
build intel "intel/2025.3.2"
echo "== fin compilación STREAM (job $SLURM_JOB_ID)"
