#!/usr/bin/env bash
#SBATCH --job-name=check-gpu-cuda
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --partition=volta
#SBATCH --gres=gpu:1
#SBATCH --account=<account>
#SBATCH --time=00:10:00
#SBATCH --output=data/raw/phaseB/check-gpu-cuda-%j.out
# Línea 4 (GPU): soporte CUDA de openmpi_gcc/5.0.5_cuda12 (ompi_info) en un nodo
# de la partición volta (en login el binario no emitía nada; se comprueba donde
# toca usarlo). Si el componente mca correspondiente no figura, OSU device-to-device
# se omite y se declara (R14.5). No se instala nada nuevo.
set -uo pipefail
OMPI=/opt/apps/openmpi_gcc/5.0.5_cuda12
echo "== nodo $(hostname -s) $(date -Is)"
echo "== ompi_info (salida completa filtrada):"
"$OMPI/bin/ompi_info" 2>&1 | head -15
echo "== componentes/parámetros CUDA:"
"$OMPI/bin/ompi_info" --param btl all --level 9 2>&1 | grep -i cuda | head -10 || true
"$OMPI/bin/ompi_info" 2>&1 | grep -ic cuda || echo "0 menciones de cuda en ompi_info"
echo "== librerías CUDA del build:"
ls "$OMPI/lib/" 2>/dev/null | grep -i cuda | head -5 || echo "(sin libs cuda en el prefijo)"
ls "$OMPI/lib/openmpi" 2>/dev/null | grep -iE "cuda|gpu" | head -5 || echo "(sin componentes cuda en lib/openmpi)"
echo "== nvcc (módulo cuda):"
module purge 2>/dev/null || true; module load cuda/12.9.1 2>/dev/null || true
nvcc --version 2>/dev/null | tail -1 || echo "(sin nvcc)"
echo "== GPU visible:"
nvidia-smi -L 2>/dev/null | head -2 || echo "(sin GPU visible)"
echo "== fin check GPU CUDA (job $SLURM_JOB_ID)"
