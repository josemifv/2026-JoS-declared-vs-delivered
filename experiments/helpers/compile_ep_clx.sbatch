#!/usr/bin/env bash
#SBATCH --job-name=compile-ep-clx
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --partition=cpu36c
#SBATCH --account=<account>
#SBATCH --time=00:20:00
#SBATCH --output=<scratch>/src/slurm-compile-ep-clx-%j.out
# EP clx (cpu36c) para la prueba de infrautilización (4ª revisión, humos 83731/83738:
# las celdas ep c36 quedaron SIN-BINARIO — solo existían ft clx, DEVIATIONS 2026-10-04).
# Misma receta que compile_ft_clx.sbatch (make.def de fase B, -march=cascadelake,
# gfortran en ambas pilas, árbol limpio por clase; solo clase D).
set -euo pipefail
source ~/cc2026/repo/clusters/local.env
SCRATCH="$TURGALIUM_SCRATCH"
W=~/cc2026/repo/instrumentation/cmdlog.sh
export CMDLOG_DIR="$SCRATCH/cc/raw/infrautil/compile-ep-clx-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="compile-ep-clx-$SLURM_JOB_ID"
mkdir -p "$CMDLOG_DIR"
MARCH=cascadelake
NPB_SRC="$SCRATCH/src/NPB3.4.1/NPB3.4-MPI"
[ -d "$NPB_SRC" ] || { echo "!! fuente NPB no encontrada: $NPB_SRC" >&2; exit 1; }
echo "== host $(hostname -s); ep clase D ($MARCH)"

rebuild_ep() { # $1 = pila; $2 = módulos
  local name="$1" mods="$2"   # (83802: el echo usaba $name antes del local, set -u)
  echo "== compilación EP $name ($MARCH)"
  module purge 2>/dev/null || true; module load $mods
  local fc; fc="$(command -v mpif90 || command -v mpifort)"
  local d="$SCRATCH/src/phaseB/npb-$name-clx"
  if [ ! -d "$d" ]; then cp -r "$NPB_SRC" "$d"; fi
  cd "$d"
  cat > config/make.def <<EOF
CC = mpicc -march=$MARCH
MPICC = mpicc -march=$MARCH
FC = $fc -march=$MARCH
MPIFC = $fc -march=$MARCH
FLINK = \$(FC)
CCFLAGS = -O3
FFLAGS = -O3 -march=$MARCH -fallow-argument-mismatch -fallow-invalid-boz
FLINKFLAGS =
RAND = randi8
RANDPAR = randi8
BINDIR = ../bin
WTIME = wtime_ompi.c
EOF
  mkdir -p bin
  make clean >/dev/null 2>&1 || true
  rm -f config/npbparams.h
  bash "$W" make ep CLASS=D 2>&1 | tail -1
  local dest="$SCRATCH/benchmarks/npb/$name/clx"
  mkdir -p "$dest"
  if [ -f bin/ep.D.x ]; then
    cp bin/ep.D.x "$dest/ep.D.x"
    echo "   ok ep.D.x ($name, $MARCH)"
  else
    echo "   !! ep.D.x no generado ($name)" >&2; exit 4
  fi
  cd "$SCRATCH/src/phaseB" 2>/dev/null || cd "$SCRATCH/src"
}
rebuild_ep gcc   "openmpi_gcc/5.0.5 ucx/1.9.0"
rebuild_ep intel "intel/2025.3.2"
echo "== fin compilación EP clx (job $SLURM_JOB_ID)"
