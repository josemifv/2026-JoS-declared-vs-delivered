#!/usr/bin/env bash
#SBATCH --job-name=block0-hpcg
#SBATCH --nodes=8
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --account=<account>
#SBATCH --time=01:00:00
#SBATCH --output=data/raw/phaseB/block0-hpcg-%j.out

# Bloque 0 del plan de fase B v2: celda de timing de HPCG (cierra D-C / R13).
# - Par: intel/mlx (mejor R2), binario compilado con g++ vía Intel MPI.
# - Configuración CMMSE (R4/R5.4, DEVIATIONS 2026-10-04): 104³ local, 60
#   s de ejecución, 512 ranks (8 nodos x 64). CON 60 s DE EJECUCIÓN EL RESULTADO NO ES
#   OFICIALMENTE VÁLIDO (el estándar exige >= 1800 s): se usa para comparar.
# - Mapa explícito de la fase A verificado por run (R10); transporte efectivo
#   registrado (nivel 1). Una sola repetición: mide duración, no mediana.
set -u
source clusters/local.env
SCRATCH="$TURGALIUM_SCRATCH"
W="$PWD/instrumentation/cmdlog.sh"
export CMDLOG_DIR="$SCRATCH/cc/raw/phaseB/block0-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="block0-$SLURM_JOB_ID"
export LEVEL1_MODE=unprivileged
HPCG="$SCRATCH/benchmarks/phaseB/hpcg/intel/xhpcg"
mkdir -p "$CMDLOG_DIR" data/raw/phaseB
echo "== bloque 0: celda de timing HPCG (job $SLURM_JOB_ID)"
echo "== nodos asignados:"; srun --ntasks=8 --ntasks-per-node=1 hostname -s | sort | tr '\n' ' '; echo

module purge 2>/dev/null || true
module load intel/2025.3.2
export I_MPI_FABRICS=ofi FI_PROVIDER=mlx I_MPI_DEBUG=5
export I_MPI_PIN_PROCESSOR_LIST="0-31,56-87"
echo "--- mapa pedido = real (R10, 512/512):"
mpirun -n 512 -ppn 64 bash -c 'echo "$(hostname -s) rank=${PMI_RANK:-NA} cpus=$(taskset -pc $$ | awk "{print \$NF}")"' > "$CMDLOG_DIR/map-check.txt" 2>&1
grep -c "cpus=" "$CMDLOG_DIR/map-check.txt"
printf "HPCG benchmark input file\nSandia National Laboratories; University of Tennessee, Knoxville\n104 104 104\n60\n" > "$CMDLOG_DIR/hpcg.dat"
( cd "$CMDLOG_DIR" \
  && T0=$(date +%s.%N) \
  && bash "$W" mpirun -n 512 -ppn 64 "$HPCG" \
  && T1=$(date +%s.%N) \
  && echo "WALL_SECONDS=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%.1f", b-a}')" | tee wall.txt ) 
echo "== resultado:"; grep -h -m1 "HPCG result is" "$CMDLOG_DIR/HPCG-Benchmark_3.1_"*.txt "$CMDLOG_DIR"/*.txt 2>/dev/null | head -2
echo "== bloque 0 terminado (job $SLURM_JOB_ID)"
