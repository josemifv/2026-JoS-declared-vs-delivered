#!/usr/bin/env bash
#SBATCH --job-name=disc_aac105
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --exclusive
#SBATCH --nodelist=aac105
#SBATCH --partition=cpu36c
#SBATCH --account=<account>
#SBATCH --time=00:20:00
#SBATCH --output=<scratch>/discovery/cpu36c/jobs/slurm-aac105-%j.out
module purge 2>/dev/null || true
export CMDLOG_DIR="<scratch>/discovery/cpu36c"
export CMDLOG_RUN_ID="disc-turgalium-20260925T220348Z-3872147"
exec "python3" "<home>/discovery/collect_node.py" \
    --mode node --cluster "turgalium" --node "aac105" \
    --out-dir "<scratch>/discovery/cpu36c" --wrapper "<home>/instrumentation/cmdlog.sh" --partition "cpu36c"
