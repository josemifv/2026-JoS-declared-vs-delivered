#!/usr/bin/env bash
# OBSOLETO, NO USAR: sustituido por experiments/ligero36_bs_gpu.sbatch (2026-10-04)
# Protocolo ligero GPU: validación de la metodología, no eje del artículo.
# Reglas: R14 (BabelStream desde fuente si no hay módulo; OSU GPU se omite si no hay
# MPI CUDA-aware instalado, y se declara). NO se construye ni instala stack MPI para GPU.
# 5 repeticiones por celda.
# Uso: sbatch ligero_gpu.sh <prueba: babelstream|osu-device>
# PLACEHOLDERS: <<<PARTITION>>> <<<NODELIST>>> <<<MODULES_GPU>>> <<<BABELSTREAM_PATH>>>
#SBATCH --job-name=cc-ligero-gpu
#SBATCH --exclusive
#SBATCH --partition=<<<PARTITION_GPU>>>
#SBATCH --gres=gpu:1
#SBATCH --output=data/raw/ligero/%x-%j.out
#SBATCH --time=01:00:00

set -euo pipefail
source clusters/local.env
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/ligero/$SLURM_JOB_ID"
export CMDLOG_RUN_ID="lig-gpu-$SLURM_JOB_ID"
export LEVEL1_MODE="${LEVEL1_MODE:?fijar LEVEL1_MODE (R14): privileged|unprivileged|auto}"

module load ${MODULES_GPU:?definir MODULES_GPU en local.env}

# Comprobación previa (R14): ¿hay MPI CUDA-aware ya instalado?
# <<<ompi_info --parsable | grep mpi_built_with_cuda_support>>> — si no, OSU device se omite y se declara.
case "${1:-}" in
  babelstream) level1_capture.sh start
               # <<<BUCLE DE REPETICIONES>>>: ./<BABELSTREAM_PATH> ... via cmdlog.sh
               level1_capture.sh stop ;;
  osu-device)  # Solo si CUDA-aware: OSU device-to-device entre 2 GPUs (misma o distinta nodo según alcance).
               # <<<BUCLE DE REPETICIONES>>> via cmdlog.sh
               ;;
  *) echo "uso: ligero_gpu.sh <babelstream|osu-device>" >&2; exit 2 ;;
esac
