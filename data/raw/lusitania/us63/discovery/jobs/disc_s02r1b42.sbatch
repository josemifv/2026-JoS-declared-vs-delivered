#!/usr/bin/env bash
#SBATCH --job-name=disc_s02r1b42
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --exclusive
#SBATCH --nodelist=s02r1b42
#SBATCH --partition=us63
#SBATCH --time=00:20:00
#SBATCH --output=<scratch>/cc/raw/lusitania/us63/discovery/jobs/slurm-s02r1b42-%j.out
module purge 2>/dev/null || true
export CMDLOG_DIR="<scratch>/cc/raw/lusitania/us63/discovery"
export CMDLOG_RUN_ID="disc-lusitania-20261015T221415Z-6171"
exec "/lusitania_apps/python/python-3.10.6/bin/python3" "<home>/discovery/collect_node.py" \
    --mode node --cluster "lusitania" --node "s02r1b42" \
    --out-dir "<scratch>/cc/raw/lusitania/us63/discovery" --wrapper "<home>/instrumentation/cmdlog.sh" --partition "us63"
