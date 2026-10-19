#!/usr/bin/env bash
#SBATCH --job-name=disc_bbp38
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --exclusive
#SBATCH --nodelist=bbp38
#SBATCH --partition=cpu48c
#SBATCH --account=<account>
#SBATCH --time=00:20:00
#SBATCH --output=<scratch>/discovery/cpu48c/jobs/slurm-bbp38-%j.out
module purge 2>/dev/null || true
export CMDLOG_DIR="<scratch>/discovery/cpu48c"
export CMDLOG_RUN_ID="disc-turgalium-20260925T220718Z-3873208"
exec "python3" "<home>/discovery/collect_node.py" \
    --mode node --cluster "turgalium" --node "bbp38" \
    --out-dir "<scratch>/discovery/cpu48c" --wrapper "<home>/instrumentation/cmdlog.sh" --partition "cpu48c"
