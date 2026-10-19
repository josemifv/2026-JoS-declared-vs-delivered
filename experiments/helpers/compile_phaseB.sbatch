#!/usr/bin/env bash
#SBATCH --job-name=compile-phaseB
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --account=<account>
#SBATCH --time=00:40:00
#SBATCH --output=data/raw/phaseB/compile-phaseB-%j.out

# Preparación de binarios de la fase B (R14.4). Se ejecuta en un NODO DE CÓMPUTO
# de cpu112c (Sapphire Rapids), nunca en login. Convenciones y flags fijados a
# priori (plan de fase B §0):
#
#  NPB 3.4.1 (misma versión que los ft.*.x existentes), kernels ep, cg, mg clase D,
#    Fortran compilado con gfortran en AMBAS pilas a través del mpif90 de cada
#    módulo (convención ya usada para ft.*.x: mismo compilador, distinta librería
#    MPI), flags -O3 -march=sapphirerapids, más los de compatibilidad de gfortran
#    para NPB 3.4.1 (-fallow-argument-mismatch -fallow-invalid-boz). Destino:
#    benchmarks/npb/<pila>/spr/ (no se sobrescribe ft.*.x).
#
#  HPCG 3.1.0 por pila con el stack ACTUAL: gcc -> mpicxx (OpenMPI 5.0.5 + g++),
#    intel -> mpicxx de Intel MPI con I_MPI_CXX=g++ (MISMO compilador que en gcc,
#    para que en fase B la unica diferencia entre pares sea la libreria MPI y el
#    transporte, no el compilador; igual criterio que NPB con gfortran). Flags
#    -O3 con objetivo Sapphire Rapids: -march=sapphirerapids en g++; el build
#    anterior con mpiicpx (-xSAPPHIRERAPIDS) se CONSERVA como artefacto
#    separado en benchmarks/phaseB/hpcg/intel-icpx/. -DHPCG_NO_OPENMP como el
#    CMMSE, SIN -ffast-math en ninguna pila (equivalencia y resultados
#    comparables). Destino NUEVO: benchmarks/phaseB/hpcg/<etiqueta>/.
#    NO se toca ~/CMMSE26/benchmarks/hpcg/ (mitad "stack CMMSE" de las anclas).
#    NOTA: estos binarios NO se usan para las anclas: la celda "stack actual"
#    de las anclas replica la configuracion del CMMSE (R4), incluidos sus flags
#    (p. ej. -ffast-math en gcc) y su compilador (icpx en la pila intel).
set -u
source clusters/local.env
SCRATCH="$TURGALIUM_SCRATCH"
# ruta ABSOLUTA: el script hace cd al directorio de build y una ruta relativa se romperia
W="$PWD/instrumentation/cmdlog.sh"
ARCH=spr                     # etiqueta de directorio (arquitectura del nodo)
MARCH=sapphirerapids          # valor real de -march de gcc/gfortran
export CMDLOG_DIR="$SCRATCH/cc/raw/phaseB/compile"
export CMDLOG_RUN_ID="compile-phaseB-$SLURM_JOB_ID"
mkdir -p "$CMDLOG_DIR" data/raw/phaseB "$SCRATCH/src/phaseB"
echo "== host $(hostname -s)  gfortran: $(command -v gfortran)  $(gfortran --version | head -1)"
echo "== ifx: $(module purge 2>/dev/null; module load intel/2025.3.2 2>/dev/null; command -v ifx)"

NPB_SRC="$SCRATCH/src/NPB3.4.1/NPB3.4-MPI"
HPCG_SRC="$HOME/CMMSE26/benchmarks/hpcg/src/hpcg-HPCG-release-3-1-0"

# ---------- NPB: ep, cg, mg clase D por pila ----------
build_npb() {  # $1 = pila; $2 = módulos
  local name="$1"
  echo "== NPB $name / $ARCH"
  module purge 2>/dev/null || true
  module load $2
  local fc; fc="$(command -v mpif90 || command -v mpifort)"
  echo "   mpif90 -> $fc ($($fc -show 2>/dev/null | head -1))"
  local d="$SCRATCH/src/phaseB/npb-$name-$ARCH"
  [ -d "$d" ] || cp -r "$NPB_SRC" "$d"
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
# make enlaza desde el subdirectorio del kernel (EP/, CG/, MG/): ../bin = bin/ del build
BINDIR = ../bin
WTIME = wtime_ompi.c
EOF
  mkdir -p bin "$SCRATCH/benchmarks/npb/$name/$ARCH"   # NPB espera bin/ en el directorio de build
  for k in ep cg mg; do
    bash "$W" make "$k" CLASS=D 2>&1 | tail -1
    local bin="bin/$k.D.x"; [ -f "$bin" ] || bin="../bin/$k.D.x"
    [ -f "$bin" ] && cp "$bin" "$SCRATCH/benchmarks/npb/$name/$ARCH/" && echo "   ok $k.D.x" || echo "   !! $k.D.x no generado"
  done
  cd "$SCRATCH/src/phaseB"
}

# ---------- HPCG 3.1.0 por pila ----------
build_hpcg() {  # $1 = dir destino; $2 = módulos; $3 = CXX; $4 = flags de arquitectura; $5 = env extra
  local name="$1" cxx="$3" archflags="$4" extra="${5:-}"
  echo "== HPCG $name ($cxx $archflags ${extra:+| $extra})"
  module purge 2>/dev/null || true
  module load $2
  unset I_MPI_CXX                            # no heredar del build anterior (rompia intel-icpx)
  [ -n "$extra" ] && eval "export $extra"   # p. ej. I_MPI_CXX=g++ (mpicxx de Intel MPI -> g++)
  local d="$SCRATCH/src/phaseB/hpcg-3.1.0-$name"
  rm -rf "$d"; cp -r "$HPCG_SRC" "$d"
  cd "$d"
  cat > setup/Make.phaseB_$name <<EOF
SHELL        = /bin/sh
CD           = cd
CP           = cp
LN_S         = ln -s -f
MKDIR        = mkdir -p
RM           = /bin/rm -f
TOUCH        = touch
TOPdir       = .
SRCdir       = \$(TOPdir)/src
INCdir       = \$(TOPdir)/src
BINdir       = \$(TOPdir)/bin
MPdir        =
MPinc        =
MPlib        =
HPCG_INCLUDES = -I\$(INCdir) -I\$(INCdir)/\$(arch) \$(MPinc)
HPCG_LIBS     =
HPCG_OPTS     = -DHPCG_NO_OPENMP
HPCG_DEFS     = \$(HPCG_OPTS) \$(HPCG_INCLUDES)
CXX          = $cxx
CXXFLAGS     = \$(HPCG_DEFS) -O3 $archflags
LINKER       = \$(CXX)
LINKFLAGS    = \$(CXXFLAGS)
ARCHIVER     = ar
ARFLAGS      = r
RANLIB       = echo
EOF
  bash "$W" ./configure phaseB_$name 2>&1 | tail -2
  bash "$W" make -j 8 2>&1 | tail -2
  mkdir -p "$SCRATCH/benchmarks/phaseB/hpcg/$name"
  if [ -x bin/xhpcg ]; then
    cp bin/xhpcg "$SCRATCH/benchmarks/phaseB/hpcg/$name/xhpcg" && echo "   ok xhpcg ($name)"
    bash "$W" ldd "$SCRATCH/benchmarks/phaseB/hpcg/$name/xhpcg" 2>&1 | grep -E "mpi|ucp|fabric" | head -3
  else
    echo "!! xhpcg NO construido ($name)"
  fi
  cd "$SCRATCH/src/phaseB"
}

build_npb gcc   "openmpi_gcc/5.0.5 ucx/1.9.0"
build_npb intel "intel/2025.3.2"
# HPCG: g++ en AMBAS pilas (misma configuracion salvo la libreria MPI)
build_hpcg gcc        "openmpi_gcc/5.0.5 ucx/1.9.0" mpicxx  "-march=$MARCH"     ""
build_hpcg intel      "intel/2025.3.2"              mpicxx  "-march=$MARCH"     "I_MPI_CXX=g++"
# Artefacto separado, conservado: build anterior con icpx
build_hpcg intel-icpx "intel/2025.3.2"              mpiicpx "-xSAPPHIRERAPIDS" ""

module purge 2>/dev/null || true
echo "== resultado =="
ls -la "$SCRATCH/benchmarks/npb/gcc/$ARCH/" "$SCRATCH/benchmarks/npb/intel/$ARCH/" 2>/dev/null | grep -E "\.x|:"
ls -la "$SCRATCH/benchmarks/phaseB/hpcg/gcc/" "$SCRATCH/benchmarks/phaseB/hpcg/intel/" 2>/dev/null | grep -E "xhpcg|:"
echo "== fin compilación fase B (job $SLURM_JOB_ID) =="
