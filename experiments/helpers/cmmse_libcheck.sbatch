#!/usr/bin/env bash
#SBATCH --job-name=cmmse-libcheck
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --account=<account>
#SBATCH --time=00:10:00
#SBATCH --output=<scratch>/src/slurm-cmmse-libcheck-%j.out
# Línea 2: librerías cargadas HOY por los binarios supervivientes del CMMSE
# (ldd estático + /proc/<pid>/maps con una ejecución mínima). R5.2.
# v2 (2026-10-04): los binarios están en install-<pila>/xhpcg (sin bin/).
B=~/CMMSE26/benchmarks
echo "== ldd de los binarios supervivientes:"
for f in $B/hpcg/install-gcc/xhpcg $B/hpcg/install-intel/xhpcg; do
  [ -f "$f" ] || { echo "  (no existe $f)"; continue; }
  echo "-- $f"; ldd "$f" | grep -E "libmpi|libucp|libblas|libopenblas|libmkl|libgfortran|libfabric" | head -6
done
echo "== OpenBLAS del CMMSE (link estático/ruta):"
find $B -maxdepth 4 -name "libopenblas*" 2>/dev/null | head -4
ls $B/openblas 2>/dev/null | head -4
echo "== /proc/<pid>/maps de una ejecución mínima (HPCG gcc, 1 rank, problema mínimo):"
D=$B/hpcg/install-gcc
printf "HPCG benchmark input file\nSandia National Laboratories; University of Tennessee, Knoxville\n16 16 16\n1\n" > hpcg_min.dat
mkdir -p minrun && cp hpcg_min.dat minrun/hpcg.dat && cd minrun
( for i in $(seq 1 30); do p=$(pgrep -x xhpcg | head -1); [ -n "$p" ] && { grep -E "libmpi|libucp|libopenblas|libblas|libmkl" /proc/$p/maps | awk "{print \$NF}" | sort -u; break; }; sleep 1; done ) &
mpirun -np 1 $D/xhpcg > hpcg_min.out 2>&1
wait
echo "-- resultado de la ejecución mínima:"; grep -m1 -E "VALID|INVALID" hpcg_min.out hpcg*.txt 2>/dev/null | head -2
echo "== fin comprobación CMMSE (job $SLURM_JOB_ID)"
