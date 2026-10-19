#!/usr/bin/env bash
#SBATCH --job-name=compile-npb
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --exclusive
#SBATCH --partition=cpu36c
#SBATCH --account=<account>
#SBATCH --time=00:20:00
#SBATCH --output=<scratch>/src/slurm-compile-npb-%j.out

# Compilación NATIVA por arquitectura (R14.4): -O3 -march=native, las mismas
# flags equivalentes para las dos pilas. La arquitectura la determina el nodo
# donde corre el job (partición del submission); el binario queda en
# benchmarks/npb/<pila>/<arch>/.
#
# Uso: sbatch [-p particion] [--gres=gpu:1] compile_npb.sbatch <arch>
#   arch = spr (b9p*: cpu112c + hosts h100) | clx (aac/acc: cpu36c) | g6240 (aap/acp: volta)
set -u
ARCH="${1:?uso: sbatch [-p particion] [--gres=gpu:1] compile_npb.sbatch <arch: spr|clx|g6240>}"
REPO=<home>
W="$REPO/instrumentation/cmdlog.sh"
SCRATCH=<scratch>
export CMDLOG_DIR="$SCRATCH/src"
export CMDLOG_RUN_ID="compile-npb-$ARCH-$(date -u +%Y%m%dT%H%M%SZ)"

set -e
cd "$SCRATCH/src"

build_stack() {   # $1 = nombre (gcc|intel), $2 = modulos, $3 = FC fallback, $4 = FFLAGS extra
    local name="$1" modulos="$2" fcfb="$3" ffx="$4"
    echo "== pila $name / arch $ARCH: $modulos =="
    module load $modulos
    local fc=mpif90
    command -v mpif90 >/dev/null || fc="$fcfb"
    local d="npb-$name-$ARCH"
    [ -d "$d" ] || cp -r NPB3.4.1/NPB3.4-MPI "$d"
    cd "$d"
    local wtime=wtime_ompi.c
    [ -f config/$wtime ] || wtime=wtime_system.c
    cat > config/make.def <<EOF
CC = mpicc -march=native
MPICC = mpicc -march=native
FC = $fc -march=native
MPIFC = $fc -march=native
FLINK = \$(FC)
CCFLAGS = -O3
FFLAGS = -O3 $ffx
FLINKFLAGS =
RAND = randi8
RANDPAR = randi8
BINDIR = ../bin
WTIME = $wtime
EOF
    mkdir -p "$SCRATCH/benchmarks/npb/$name/$ARCH"
    for clase in B C D; do
        bash "$W" bash -lc "make ft CLASS=$clase" 2>&1 | tail -2
        [ -f "bin/ft.$clase.x" ] && cp "bin/ft.$clase.x" "$SCRATCH/benchmarks/npb/$name/$ARCH/"
    done
    cd "$SCRATCH/src"
    module purge 2>/dev/null || true
}

build_stack gcc "openmpi_gcc/5.0.5 ucx/1.9.0" "mpifort" "-fallow-argument-mismatch -fallow-invalid-boz"
build_stack intel "intel/2025.3.2" "mpiifx" ""

echo "== binarios resultantes ($ARCH) =="
ls -la "$SCRATCH/benchmarks/npb/gcc/$ARCH/" "$SCRATCH/benchmarks/npb/intel/$ARCH/"
echo "== fin compilación NPB ($ARCH) =="
