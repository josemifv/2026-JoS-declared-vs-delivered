#!/usr/bin/env bash
#SBATCH --job-name=compile-ft-spr
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --account=<account>
#SBATCH --time=00:20:00
#SBATCH --output=<scratch>/src/slurm-compile-ft-spr-%j.out
# *** SIN USO desde D19 (2026-10-06): FT vuelve a la clase D en la infrautilización
# (D19 revierte D3; el ft.C.x recompilado no se usa; L7a-v2 no invoca este job). ***
# ft.C.x de spr RECOMPILADO con el make.def de fase B (-O3 -march=sapphirerapids)
# antes de la prueba de infrautilización (D3, DEVIATIONS 2026-10-06; launch L7a v1).
# MOTIVO (verificado 2026-10-06): los ft.C.x de spr existentes datan del 30-09
# 17:42 (era -march=native, la misma noche del bug de builds sin `make clean` que
# produjo ft.C.x/ft.D.x clase B relabeled en clx — DEVIATIONS 2026-10-04); su clase
# NO es fiable y su make.def no es el de fase B. Los ft.C.x de clx SÍ están
# verificados (calib36 83394/83395, duraciones y Size de clase C).
# Convención de fase B: misma fuente y flags para ambas pilas vía el mpif90 de cada
# módulo; solo cambia la librería MPI. El binario anterior se conserva .pre-v8.
# §8: traza por cmdlog; árbol limpio por clase.
set -euo pipefail
source ~/cc2026/repo/clusters/local.env
SCRATCH="$TURGALIUM_SCRATCH"
W=~/cc2026/repo/instrumentation/cmdlog.sh
export CMDLOG_DIR="$SCRATCH/cc/raw/phaseB/compile-ft-spr-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="compile-ft-spr-$SLURM_JOB_ID"
mkdir -p "$CMDLOG_DIR"
MARCH=sapphirerapids
NPB_SRC="$SCRATCH/src/NPB3.4.1/NPB3.4-MPI"
[ -d "$NPB_SRC" ] || { echo "!! fuente NPB no encontrada: $NPB_SRC" >&2; exit 1; }
echo "== host $(hostname -s); ft clase C ($MARCH)"

rebuild_ft_c() { # $1 = pila; $2 = módulos
  local name="$1" mods="$2"
  echo "== recompilación FT C $name ($MARCH)"
  module purge 2>/dev/null || true; module load $mods
  local fc; fc="$(command -v mpif90 || command -v mpifort)"
  local d="$SCRATCH/src/phaseB/npb-$name-spr"
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
  local dest="$SCRATCH/benchmarks/npb/$name/spr"
  mkdir -p "$dest"
  # Árbol limpio por clase (BUG 83301/83312, DEVIATIONS 2026-10-04)
  make clean >/dev/null 2>&1 || true
  rm -f config/npbparams.h
  bash "$W" make ft CLASS=C 2>&1 | tail -1
  if [ -f bin/ft.C.x ]; then
    if [ -f "$dest/ft.C.x" ] && [ ! -f "$dest/ft.C.x.pre-v8" ]; then
      cp "$dest/ft.C.x" "$dest/ft.C.x.pre-v8"
    fi
    cp bin/ft.C.x "$dest/ft.C.x"
    echo "   ok ft.C.x ($name, $MARCH): $(sha256sum "$dest/ft.C.x" | cut -c1-16)"
  else
    echo "   !! ft.C.x no generado ($name)" >&2
    exit 4
  fi
  cd "$SCRATCH/src/phaseB" 2>/dev/null || cd "$SCRATCH/src"
}
rebuild_ft_c gcc   "openmpi_gcc/5.0.5 ucx/1.9.0"
rebuild_ft_c intel "intel/2025.3.2"
echo "== fin compilación FT spr clase C (job $SLURM_JOB_ID)"
