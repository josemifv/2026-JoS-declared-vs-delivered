#!/usr/bin/env bash
#SBATCH --job-name=compile-osu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --exclusive
#SBATCH --partition=cpu36c
#SBATCH --account=<account>
#SBATCH --time=00:20:00
#SBATCH --output=<scratch>/src/slurm-compile-osu-%j.out

# Compilación de OSU POR PILA (R14.4): el único build existente estaba enlazado
# a Open MPI (libmpi.so.40 de openmpi_gcc), y bajo la pila intel los procesos
# quedaban singleton (la libmpi de Open MPI no entiende el cableado de Hydra).
# El binario por pila queda en benchmarks/osu/<pila>/libexec/osu-micro-benchmarks/.
# El build original (benchmarks/osu/libexec) se conserva como evidencia.
#
# Uso: sbatch compile_osu.sbatch

set -u
REPO=<home>
SCRATCH=<scratch>
W="$REPO/instrumentation/cmdlog.sh"
export CMDLOG_DIR="$SCRATCH/src"
export CMDLOG_RUN_ID="compile-osu-$(date -u +%Y%m%dT%H%M%SZ)"

set -e
cd "$SCRATCH/src"
SRC=osu-micro-benchmarks-7.4

build_stack() {   # $1 = gcc | intel
    local pila="$1"
    echo "== OSU / pila $pila =="
    module purge 2>/dev/null || true
    case "$pila" in
        gcc)   module load openmpi_gcc/5.0.5 ucx/1.9.0 ;;
        intel) module load intel/2025.3.2 ;;
    esac
    local d="osu-$pila"
    [ -d "$d" ] || cp -r "$SRC" "$d"
    cd "$d"
    bash "$W" make distclean > /dev/null 2>&1 || true
    bash "$W" ./configure --prefix="$SCRATCH/benchmarks/osu/$pila" CC=mpicc > /dev/null
    bash "$W" make > /dev/null
    make install > /dev/null
    cd "$SCRATCH/src"
    module purge 2>/dev/null || true
}

build_stack gcc
build_stack intel

echo "== binarios resultantes =="
ls "$SCRATCH/benchmarks/osu/gcc/libexec/osu-micro-benchmarks/mpi/pt2pt/" | head -4
ls "$SCRATCH/benchmarks/osu/intel/libexec/osu-micro-benchmarks/mpi/pt2pt/" | head -4
echo "== fin compilación OSU =="
