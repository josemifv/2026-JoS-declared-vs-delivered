#!/usr/bin/env bash
#SBATCH --job-name=compile-stream-clx
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --partition=cpu36c
#SBATCH --account=<account>
#SBATCH --time=00:10:00
#SBATCH --output=<scratch>/src/slurm-compile-stream-clx-%j.out
# STREAM clx (cpu36c) para la prueba de infrautilización (4ª revisión, punto 3):
# misma fuente única que compile_stream.sbatch (scratch/src/stream/stream.c) pero
# con -march=cascadelake y compilado en un NODO de cpu36c (orden de la persona:
# compilar antes del humo de infrautil; sin binario, las celdas STREAM c36 quedan
# SIN-BINARIO). Destino: benchmarks/stream/<pila>/stream_clx (convención de rutas
# de infrautil.sh v4). §8: falla si falta la fuente; traza por cmdlog.
# Nota (DEVIATIONS 2026-10-04): sin -ffast-math; los hilos se pinean en
# infrautil.sh con GOMP_CPU_AFFINITY / KMP_AFFINITY.
set -euo pipefail
source ~/cc2026/repo/clusters/local.env
SCRATCH="$TURGALIUM_SCRATCH"
W=~/cc2026/repo/instrumentation/cmdlog.sh
export CMDLOG_DIR="$SCRATCH/cc/raw/infrautil/compile-stream-clx-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="compile-stream-clx-$SLURM_JOB_ID"
mkdir -p "$CMDLOG_DIR"
SRC="$SCRATCH/src/stream/stream.c"
[ -f "$SRC" ] || { echo "!! fuente no encontrada: $SRC" >&2; exit 1; }
echo "== host $(hostname -s); STREAM cascadelake por pila"

build() { # $1 = pila; $2 = módulos
  echo "== STREAM $1 (cascadelake)"
  module purge 2>/dev/null || true; module load $2
  local d="$SCRATCH/benchmarks/stream/$1"
  mkdir -p "$d"
  bash "$W" mpicc -fopenmp -O3 -march=cascadelake "$SRC" -o "$d/stream_clx" -lm 2>&1 | tail -2
  if [ -x "$d/stream_clx" ]; then echo "   ok: $d/stream_clx"; else echo "   !! no generado ($1)" >&2; exit 4; fi
}
build gcc   "openmpi_gcc/5.0.5 ucx/1.9.0"
build intel "intel/2025.3.2"
echo "== fin compilación STREAM clx (job $SLURM_JOB_ID)"
