#!/usr/bin/env bash
#SBATCH --job-name=probe-r14-h100
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --exclusive
#SBATCH --partition=h100
#SBATCH --gres=gpu:1
#SBATCH --account=<account>
#SBATCH --time=00:05:00
#SBATCH --output=<scratch>/probe_level1/slurm-probe-h100-%j.out
set -u
REPO=<home>
W="$REPO/instrumentation/cmdlog.sh"
export CMDLOG_DIR=<scratch>/probe_level1
export CMDLOG_RUN_ID="probe-r14-$SLURM_JOB_NAME-$(date -u +%Y%m%dT%H%M%SZ)"
echo "== nodo: $(hostname) =="
echo "== identidad =="
bash "$W" bash -lc 'id --user --name' || true
echo "== A. turbostat =="
bash "$W" bash -lc 'command -v turbostat && turbostat -q sleep 1' || true
echo "== B. RAPL por sysfs (sin privilegios) =="
bash "$W" bash -lc 'cat /sys/class/powercap/intel-rapl:0/energy_uj; sleep 1; cat /sys/class/powercap/intel-rapl:0/energy_uj' || true
echo "== C. frecuencias por cpufreq =="
bash "$W" bash -lc 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq' || true
echo "== D. contadores IB por sysfs =="
bash "$W" bash -lc 'c=$(ls /sys/class/infiniband/*/ports/*/counters/port_xmit_data 2>/dev/null | head -1); echo "fichero: $c"; [ -n "$c" ] && cat "$c"' || true
echo "== E. perfquery =="
bash "$W" bash -lc 'command -v perfquery && perfquery 2>&1 | head -5' || true
echo "== fin de sonda =="
