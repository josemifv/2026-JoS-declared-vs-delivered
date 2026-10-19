#!/usr/bin/env bash
#SBATCH --job-name=disc_b9p17
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --exclusive
#SBATCH --nodelist=b9p17
#SBATCH --partition=h100
#SBATCH --account=<account>
#SBATCH --time=00:20:00
#SBATCH --output=<scratch>/discovery/h100/jobs/slurm-b9p17-%j.out
module purge 2>/dev/null || true
export CMDLOG_DIR="<scratch>/discovery/h100"
export CMDLOG_RUN_ID="disc-turgalium-20260925T220012Z-3871120"
exec "python3" "<home>/discovery/collect_node.py" \
    --mode node --cluster "turgalium" --node "b9p17" \
    --out-dir "<scratch>/discovery/h100" --wrapper "<home>/instrumentation/cmdlog.sh" --partition "h100"
