#!/usr/bin/env bash
# T50 L16b: derivado de experiments/portable/compila.sbatch
# (SHA256 b3afdcfbf559c6ca122171d9a774a9a55e82a6a699c6324100857908ac29feb3)
# por la orden informes/ordenes/2026-10-15-T50-resolucion.md. Cambios: nombre del job y,
# además, STREAM 40M con la pila gnu para la equivalencia de us63, con la fuente y
# las opciones de equiv.sbatch v1 (SHA256 9bcbeb74385c563fcef6fd0b358db76cf8ea6b4f6238a48526cd982c96ea77dc)
# salvo -march, que sale del perfil; la fuente se comprueba antes de compilar nada.
# Orígenes: experiments/helpers/compile_osu.sbatch y compile_npb.sbatch.
# SHA256 OSU: 53871989fceb9aa1295923c99e45857391be128c844cc856a7909b4fb67a74d6
# SHA256 NPB: 04005f0d0f93a82b1f25160fd37fb06685a75198d95e1149157d637745f777f1
# T29/R14.4: mismas fuentes; EP/FT C/D, rutas por perfil.
# T40: informes/ordenes/2026-10-11-T40-osu-parcial.md autoriza make -k
# e instalación parcial OSU; los cinco binarios del estudio son obligatorios.
#SBATCH --job-name=us63-compila
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
    printf 'STREAM 40M bin=%s/benchmarks/stream/gnu/%s/stream_40M flags=-fopenmp -O3 -march=%s\n' \
        "$SCRATCH" "$PARTITION" "$MARCH"
    exit 0
fi
init_job compila
for src in osu-micro-benchmarks-7.4 NPB3.4.1/NPB3.4-MPI; do
    [ -d "$SCRATCH/src/$src" ] || { printf 'falta fuente %s\n' "$src" >&2; exit 3; }
done
STREAM_SRC="$SCRATCH/src/stream/stream.c"
STREAM_SOURCE_SHA=a52bae5e175bea3f7832112af9c085adab47117f7d2ce219165379849231692b
STREAM_BIN="$SCRATCH/benchmarks/stream/gnu/$PARTITION/stream_40M"
actual="$(sha256sum < "$STREAM_SRC")" || { printf 'falta fuente STREAM\n' >&2; exit 3; }
[ "${actual%% *}" = "$STREAM_SOURCE_SHA" ] || { printf 'fuente STREAM distinta\n' >&2; exit 3; }
[ ! -e "$STREAM_BIN" ] && [ ! -e "$STREAM_BIN.sha256" ] || { printf 'STREAM ya existe: no se reutiliza\n' >&2; exit 3; }
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
load_stack gnu
mkdir -p "$(dirname "$STREAM_BIN")"
bash "$W" mpicc --version
# Orden 40M: sin -mcmodel; cualquier fallo de enlace termina aquí.
bash "$W" mpicc -fopenmp -O3 "-march=$MARCH" -DSTREAM_ARRAY_SIZE=40000000 \
    "$STREAM_SRC" -o "$STREAM_BIN" -lm
[ -x "$STREAM_BIN" ] || exit 3
sha256sum < "$STREAM_BIN" | awk '{print $1}' > "$STREAM_BIN.sha256"
cp "$STREAM_BIN.sha256" "$CMDLOG_DIR/stream.sha256"
linkage="$(bash "$W" ldd "$STREAM_BIN")" || { printf '%s\n' "$linkage" >&2; exit 3; }
printf '%s\n' "$linkage"
if grep -q 'not found' <<< "$linkage"; then
    printf 'biblioteca STREAM no resuelta\n' >&2; exit 3
fi
cat "$CMDLOG_DIR/stream.sha256"
module purge
