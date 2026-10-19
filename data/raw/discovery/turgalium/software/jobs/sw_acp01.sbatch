#!/usr/bin/env bash
#SBATCH --job-name=sw_acp01
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --nodelist=acp01
#SBATCH --partition=volta
#SBATCH --gres=gpu:1
#SBATCH --account=<account>
#SBATCH --time=00:10:00
#SBATCH --output=<scratch>/discovery/software/jobs/slurm-acp01-%j.out
module purge 2>/dev/null || true
export CMDLOG_DIR=<scratch>/discovery/software
export CMDLOG_RUN_ID=sw-acp01
export DISCOVERY_MODULES='openmpi_gcc/5.0.5 ucx/1.9.0;intel/2025.3.2;cuda/12.9.1 openmpi_gcc/5.0.5_cuda12'
exec python3 <home>/discovery/collect_node.py --mode login --cluster turgalium --node acp01 --partition volta --out-dir <scratch>/discovery/software --wrapper <home>/instrumentation/cmdlog.sh
