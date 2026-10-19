#!/usr/bin/env bash
# Orígenes: experiments/helpers/compile_osu.sbatch y compile_npb.sbatch.
# SHA256 OSU: 53871989fceb9aa1295923c99e45857391be128c844cc856a7909b4fb67a74d6
# SHA256 NPB: 04005f0d0f93a82b1f25160fd37fb06685a75198d95e1149157d637745f777f1
# T29/R14.4: mismas fuentes; EP/FT C/D, rutas por perfil.
# T40: informes/ordenes/2026-10-11-T40-osu-parcial.md autoriza make -k
# e instalación parcial OSU; los cinco binarios del estudio son obligatorios.
#SBATCH --job-name=portable-compila
#SBATCH --exclusive
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=01:00:00
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")/../..}"
source experiments/portable/perfil.sh
if [ "${DRY_RUN:-0}" = 1 ]; then
    describe_profile
    for pila in gnu intel; do
        printf 'OSU 7.4 destino=%s/benchmarks/osu/%s/%s\n' "$SCRATCH" "$pila" "$PARTITION"
        for kernel in ep ft; do
            for clase in C D; do
                printf 'NPB 3.4.1 bin=%s/benchmarks/npb/%s/%s/%s.%s.x flags=-O3 -march=%s\n' \
                    "$SCRATCH" "$pila" "$PARTITION" "$kernel" "$clase" "$MARCH"
            done
        done
    done
    exit 0
fi
init_job compila
for src in osu-micro-benchmarks-7.4 NPB3.4.1/NPB3.4-MPI; do
    [ -d "$SCRATCH/src/$src" ] || { printf 'falta fuente %s\n' "$src" >&2; exit 3; }
done
for pila in gnu intel; do
    load_stack "$pila"
    module list > "$CMDLOG_DIR/modules-$pila.txt" 2>&1
    cd "$SCRATCH/src"
    build="osu-$pila-$PARTITION-$SLURM_JOB_ID"
    cp -r osu-micro-benchmarks-7.4 "$build"
    cd "$build"
    bash "$W" make distclean || true
    bash "$W" ./configure --prefix="$SCRATCH/benchmarks/osu/$pila/$PARTITION" CC=mpicc CXX=mpicxx
    bash "$W" make -k || true
    rm -rf "$SCRATCH/benchmarks/osu/$pila/$PARTITION"
    bash "$W" make -k install || true
    for benchmark in osu_latency osu_bw osu_bibw osu_allreduce osu_alltoall; do
        subdir=pt2pt
        case "$benchmark" in osu_allreduce|osu_alltoall) subdir=collective;; esac
        osu="$SCRATCH/benchmarks/osu/$pila/$PARTITION/libexec/osu-micro-benchmarks/mpi/$subdir/$benchmark"
        [ -x "$osu" ] || { printf 'falta binario OSU: %s\n' "$benchmark" >&2; exit 3; }
        bash "$W" sha256sum "$osu"
        linkage="$(bash "$W" ldd "$osu")" || { printf '%s\n' "$linkage" >&2; exit 3; }
        printf '%s\n' "$linkage"
        if grep -q 'not found' <<< "$linkage"; then
            printf 'biblioteca OSU no resuelta: %s\n' "$benchmark" >&2; exit 3
        fi
    done
    cd "$SCRATCH/src"
    build="npb-$pila-$PARTITION-$SLURM_JOB_ID"
    cp -r NPB3.4.1/NPB3.4-MPI "$build"
    cd "$build"
    fc=mpif90; command -v "$fc" >/dev/null || {
        case "$pila" in gnu) fc=mpifort;; intel) fc=mpiifx;; esac
    }
    bash "$W" "$fc" --version
    ffx=""
    if "$fc" --version 2>/dev/null | grep -q 'GNU Fortran'; then
        major="$("$fc" --version 2>/dev/null | sed -nE 's/.*GNU Fortran[^0-9]*([0-9]+).*/\1/p' | head -1)"
        if [ "${major:-0}" -ge 10 ]; then
            ffx="-fallow-argument-mismatch -fallow-invalid-boz"
        fi
    fi
    wtime=wtime_ompi.c; [ -f "config/$wtime" ] || wtime=wtime_system.c
    printf '%s\n' "CC = mpicc -march=$MARCH" "MPICC = mpicc -march=$MARCH" \
        "FC = $fc -march=$MARCH" "MPIFC = $fc -march=$MARCH" 'FLINK = $(FC)' \
        'CCFLAGS = -O3' "FFLAGS = -O3 $ffx" 'FLINKFLAGS =' \
        'RAND = randi8' 'RANDPAR = randi8' 'BINDIR = ../bin' "WTIME = $wtime" > config/make.def
    dest="$SCRATCH/benchmarks/npb/$pila/$PARTITION"
    mkdir -p "$dest"
    for kernel in ep ft; do
        for clase in C D; do
            bash "$W" make clean || true
            rm -f config/npbparams.h
            bash "$W" make "$kernel" "CLASS=$clase"
            [ -x "bin/$kernel.$clase.x" ] || exit 3
            bash "$W" cp "bin/$kernel.$clase.x" "$dest/"
            bash "$W" sha256sum "$dest/$kernel.$clase.x"
            bash "$W" ldd "$dest/$kernel.$clase.x"
        done
    done
done
module purge
