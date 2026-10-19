#!/usr/bin/env bash
#SBATCH --job-name=compile-ft-clx
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --partition=cpu36c
#SBATCH --account=<account>
#SBATCH --time=00:20:00
#SBATCH --output=<scratch>/src/slurm-compile-ft-clx-%j.out
# Línea 3 (cpu36c): ft.*.x de clx recompilados con el make.def de fase B
# (-O3 -march=cascadelake) en un nodo de cpu36c, antes de usarlos (orden de la
# persona, 2026-10-04). Los binarios antiguos se conservan con sufijo .pre-faseB.
# Compilador: gfortran en ambas pilas vía el mpif90 de cada módulo (convención de
# fase B: misma diferencia entre pares = solo la librería MPI).
# §8: falla con error si falta fuente o fuente NPB; traza por cmdlog.
set -euo pipefail
source ~/cc2026/repo/clusters/local.env
SCRATCH="$TURGALIUM_SCRATCH"
W=~/cc2026/repo/instrumentation/cmdlog.sh
export CMDLOG_DIR="$SCRATCH/cc/raw/phaseB/compile-ft-clx-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="compile-ft-clx-$SLURM_JOB_ID"
mkdir -p "$CMDLOG_DIR"
MARCH=cascadelake
NPB_SRC="$SCRATCH/src/NPB3.4.1/NPB3.4-MPI"
[ -d "$NPB_SRC" ] || { echo "!! fuente NPB no encontrada: $NPB_SRC" >&2; exit 1; }
echo "== host $(hostname -s); ft por clase B/C/D ($MARCH)"

rebuild_ft() { # $1 = pila; $2 = módulos
  local name="$1" mods="$2" cls
  echo "== recompilación FT $name ($MARCH)"
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
  local dest="$SCRATCH/benchmarks/npb/$name/clx"
  mkdir -p "$dest"
  for cls in B C D; do
    if [ -f "$dest/ft.$cls.x" ] && [ ! -f "$dest/ft.$cls.x.pre-faseB" ]; then
      cp "$dest/ft.$cls.x" "$dest/ft.$cls.x.pre-faseB"
    fi
    # BUG 83301/83312 (DEVIATIONS 2026-10-04): sin limpieza, los builds C y D
    # reutilizaban objetos de clase B ("Nothing to be done") y los binarios
    # ft.C.x/ft.D.x eran clase B relabeled. Árbol limpio por clase.
    make clean >/dev/null 2>&1 || true
    rm -f config/npbparams.h
    bash "$W" make ft CLASS=$cls 2>&1 | tail -1
    if [ -f bin/ft.$cls.x ]; then
      cp bin/ft.$cls.x "$dest/ft.$cls.x"
      echo "   ok ft.$cls.x ($name, $MARCH)"
    else
      echo "   !! ft.$cls.x no generado ($name) (puede no existir antes tampoco)" >&2
    fi
  done
  cd "$SCRATCH/src/phaseB" 2>/dev/null || cd "$SCRATCH/src"
}
rebuild_ft gcc   "openmpi_gcc/5.0.5 ucx/1.9.0"
rebuild_ft intel "intel/2025.3.2"
echo "== fin compilación FT clx (job $SLURM_JOB_ID)"
