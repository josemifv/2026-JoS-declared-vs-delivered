#!/usr/bin/env bash
#SBATCH --job-name=disc_acp02
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --exclusive
#SBATCH --nodelist=acp02
#SBATCH --partition=volta
#SBATCH --account=<account>
#SBATCH --time=00:20:00
#SBATCH --output=<scratch>/discovery/volta/jobs/slurm-acp02-%j.out
module purge 2>/dev/null || true
export CMDLOG_DIR="<scratch>/discovery/volta"
export CMDLOG_RUN_ID="disc-turgalium-20260925T220239Z-3871861"
exec "python3" "<home>/discovery/collect_node.py" \
    --mode node --cluster "turgalium" --node "acp02" \
    --out-dir "<scratch>/discovery/volta" --wrapper "<home>/instrumentation/cmdlog.sh" --partition "volta"
