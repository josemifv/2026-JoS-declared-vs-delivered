#!/usr/bin/env bash
#SBATCH --job-name=compile-stream-big
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --account=<account>
#SBATCH --time=00:20:00
#SBATCH --output=data/raw/infrautil/compile-stream-big-%j.out
# STREAM con el array GRANDE para la prueba de infrautilización (Prompt C, 3.7,
# 2026-10-06): la regla de STREAM pide cada array >= 4x la suma de las cachés de
# último nivel. En b9p son 2 x 105 MB → cada array necesita >= 105 M elementos.
# HOY el tamaño NO se fija al compilar: helpers/compile_stream.sbatch:31 compila
# sin -DSTREAM_ARRAY_SIZE y la fuente fija el defecto en stream.c:93-94
# (#ifndef STREAM_ARRAY_SIZE / #define STREAM_ARRAY_SIZE 10000000 — 10 M elementos,
# 80 MB por array, muy por debajo de la regla). Se recompila con
# -DSTREAM_ARRAY_SIZE=200000000 -mcmodel=medium (1,6 GB por array, 4,8 GB en total:
# cabe en cpu112c y en cpu36c de 192 GB).
# spr (sapphirerapids) y clx (cascadelake), solo gcc (D20).
# Los binarios _200M son independientes: el STREAM de fase B NO se toca.
# Tras compilar, se verifica con 1 hilo que la salida imprime
# "Array size = 200000000" (Prompt C, 3.7).
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env
SCRATCH="$TURGALIUM_SCRATCH"
W="$PWD/instrumentation/cmdlog.sh"
export CMDLOG_DIR="$SCRATCH/cc/raw/infrautil/compile-stream-big-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="compile-stream-big-$SLURM_JOB_ID"
mkdir -p "$CMDLOG_DIR"
SRC="$SCRATCH/src/stream/stream.c"
[ -f "$SRC" ] || { echo "!! fuente no encontrada: $SRC" >&2; exit 1; }
SIZE=200000000

build() { # $1 = arch (spr|clx); $2 = -march
  local arch="$1" march="$2"
  echo "== STREAM gcc/$arch array=$SIZE ($march)"
  module purge 2>/dev/null || true; module load openmpi_gcc/5.0.5 ucx/1.9.0
  local d="$SCRATCH/benchmarks/stream/gcc"
  local bin="$d/stream_${arch}_200M"
  mkdir -p "$d"
  bash "$W" mpicc -fopenmp -O3 $march -mcmodel=medium -DSTREAM_ARRAY_SIZE=$SIZE \
      "$SRC" -o "$bin" -lm
  [ -x "$bin" ] || { echo "   !! no generado (gcc/$arch)" >&2; exit 4; }
  # verificación del tamaño impreso (Prompt C, 3.7): 1 hilo, salida a cmdlog
  local out
  out="$(OMP_NUM_THREADS=1 bash "$W" "$bin" 2>&1)"
  echo "$out" > "$CMDLOG_DIR/verify-gcc-$arch.log"
  grep -q "Array size = $SIZE" "$CMDLOG_DIR/verify-gcc-$arch.log" \
    || { echo "   !! la salida no imprime 'Array size = $SIZE' (gcc/$arch)" >&2; exit 5; }
  echo "   ok: stream_${arch}_200M imprime Array size = $SIZE"
}
build spr "-march=sapphirerapids"
build clx "-march=cascadelake"
echo "== fin compilación STREAM big (job $SLURM_JOB_ID)"
