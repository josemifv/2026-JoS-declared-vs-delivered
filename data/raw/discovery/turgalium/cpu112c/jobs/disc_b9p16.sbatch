#!/usr/bin/env bash
#SBATCH --job-name=disc_b9p16
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --exclusive
#SBATCH --nodelist=b9p16
#SBATCH --partition=cpu112c
#SBATCH --account=<account>
#SBATCH --time=00:20:00
#SBATCH --output=<scratch>/discovery/cpu112c/jobs/slurm-b9p16-%j.out
module purge 2>/dev/null || true
export CMDLOG_DIR="<scratch>/discovery/cpu112c"
export CMDLOG_RUN_ID="disc-turgalium-20260925T220118Z-3871628"
exec "python3" "<home>/discovery/collect_node.py" \
    --mode node --cluster "turgalium" --node "b9p16" \
    --out-dir "<scratch>/discovery/cpu112c" --wrapper "<home>/instrumentation/cmdlog.sh" --partition "cpu112c"
