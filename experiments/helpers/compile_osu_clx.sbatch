#!/usr/bin/env bash
#SBATCH --job-name=compile-osu-clx
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --partition=cpu36c
#SBATCH --account=<account>
#SBATCH --time=00:30:00
#SBATCH --output=<scratch>/src/slurm-compile-osu-clx-%j.out
# Línea 3: OSU micro-benchmarks compilado en un nodo de cpu36c (clx, Cascade
# Lake) por pila, para el protocolo ligero E-f (R14.4). El OSU existente se
# construyó sin separación de arquitectura; este build clx es nuevo.
# v2 (2026-10-04): la fuente es 7.4 (la 5.9 no existe en scratch) y se copia
# desde $SCRATCH/src/osu-micro-benchmarks-7.4 con ruta absoluta; la v1 extraía
# en src/phaseB y comprobaba dentro de $d, por lo que nunca la encontraba.
# v3 (2026-10-04): se compila desde el tarball limpio (--strip-components=1);
# la v2 copiaba el árbol YA CONFIGURADO en cpu112c (objetos spr horneados) y
# make no reconstruía ("Nothing to be done" gcc, Error 1 intel).
# v4 (2026-10-04): configure --prefix + make install (patrón de
# compile_osu.sbatch, layout libexec/osu-micro-benchmarks/); en OSU 7.4 los
# binarios del árbol de build están en c/mpi/pt2pt/standard/, no en mpi/pt2pt.
set -u
source ~/cc2026/repo/clusters/local.env
SCRATCH=$TURGALIUM_SCRATCH
W=~/cc2026/repo/instrumentation/cmdlog.sh
export CMDLOG_DIR="$SCRATCH/cc/raw/phaseB/compile-osu-clx-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="compile-osu-clx-$SLURM_JOB_ID"
mkdir -p "$CMDLOG_DIR"
echo "== host $(hostname -s)"
TARBALL="$SCRATCH/src/osu-micro-benchmarks-7.4.tar.gz"
[ -f "$TARBALL" ] || { echo "!! tarball OSU no encontrado en $TARBALL"; exit 1; }
build() { # $1 = pila; $2 = modulos; $3 = cc wrapper
  echo "== OSU $1 (clx)"
  module purge 2>/dev/null || true; module load $2
  local d=$SCRATCH/src/phaseB/osu-7.4-$1-clx
  rm -rf "$d" && mkdir -p "$d" && cd "$d"
  tar xf "$TARBALL" --strip-components=1 || { echo "!! extracción fallida"; exit 1; }
  local dest=$SCRATCH/benchmarks/osu/$1/clx
  bash $W ./configure --prefix="$dest" CC=$3 FC=mpifort CFLAGS="-O3 -march=cascadelake" 2>&1 | tail -2
  bash $W make -j 8 2>&1 | tail -2
  bash $W make install 2>&1 | tail -1
  if [ -d "$dest/libexec/osu-micro-benchmarks/mpi/pt2pt" ]; then
    echo "   ok OSU $1 clx instalado en $dest"
  else
    echo "   !! OSU $1 clx no construido"
  fi
  cd $SCRATCH/src/phaseB
}
build gcc   "openmpi_gcc/5.0.5 ucx/1.9.0" mpicc
build intel "intel/2025.3.2"              mpicc
echo "== fin compilación OSU clx (job $SLURM_JOB_ID)"
