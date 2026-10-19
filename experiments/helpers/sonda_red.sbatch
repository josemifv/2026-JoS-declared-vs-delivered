#!/usr/bin/env bash
#SBATCH --job-name=cc-sonda-b9p07
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --nodes=9
#SBATCH --time=00:30:00
#SBATCH --output=data/raw/b9p07/sonda-red-%j.out
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}" || exit 1
mkdir -p data/raw/b9p07
TMP_DIR="data/raw/b9p07/.sonda-red-${SLURM_JOB_ID}"
mkdir -p "$TMP_DIR"
export TMP_DIR
srun --ntasks=9 --ntasks-per-node=1 bash -c '
  out="$TMP_DIR/node-${SLURM_PROCID}.out"
  {
    echo "===== hostname: $(hostname -s) ====="
    echo "--- uname -r"; uname -r || echo "NO DISPONIBLE: uname -r"
    # v2 (persona, orden informes/ordenes/2026-10-09-T26-cierre.md): fw_ver, board_id y hca_type
    # son atributos del dispositivo, no del puerto; ibstat si existe; y «module» garantizado
    # dentro de srun (si la función no llega exportada, se carga la inicialización del sistema).
    for dev in /sys/class/infiniband/*; do
      [ -d "$dev" ] || continue
      for attr in fw_ver board_id hca_type; do
        if [ -r "$dev/$attr" ]; then printf "%s: " "$dev/$attr"; cat "$dev/$attr"; else echo "NO DISPONIBLE: $dev/$attr"; fi
      done
    done
    echo "--- ibstat"; command -v ibstat >/dev/null && ibstat || echo "NO DISPONIBLE: ibstat"
    for port in /sys/class/infiniband/*/ports/*; do
      [ -d "$port" ] || continue
      for attr in state phys_state rate link_layer; do
        if [ -r "$port/$attr" ]; then printf "%s: " "$port/$attr"; cat "$port/$attr"; else echo "NO DISPONIBLE: $port/$attr"; fi
      done
    done
    echo "--- ofed_info -s"; command -v ofed_info >/dev/null && ofed_info -s || echo "NO DISPONIBLE: ofed_info -s"
    echo "--- lscpu"; command -v lscpu >/dev/null && lscpu | grep -F -e "Model name" -e "CPU MHz" -e "NUMA node(s)" || echo "NO DISPONIBLE: lscpu"
    if [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then echo -n "scaling_governor: "; cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor; else echo "NO DISPONIBLE: scaling_governor cpu0"; fi
    if ! type module >/dev/null 2>&1; then
      for init in /etc/profile.d/modules.sh /etc/profile.d/lmod.sh /usr/share/lmod/lmod/init/bash /usr/share/Modules/init/bash; do
        [ -r "$init" ] && . "$init" && break
      done
    fi
    type module >/dev/null 2>&1 && echo "--- module: disponible" || echo "NO DISPONIBLE: module"
    module purge 2>/dev/null || true
    if module load openmpi_gcc/5.0.5 ucx/1.9.0 2>/dev/null; then command -v ucx_info >/dev/null && { echo "--- ucx_info -v"; ucx_info -v; } || echo "NO DISPONIBLE: ucx_info -v"; else echo "NO DISPONIBLE: módulo gcc/ucx"; fi
    module purge 2>/dev/null || true
    if module load intel/2025.3.2 2>/dev/null; then command -v fi_info >/dev/null && { echo "--- fi_info --version"; fi_info --version; echo "--- fi_info -p mlx -l"; fi_info -p mlx -l; } || echo "NO DISPONIBLE: módulo intel"; else echo "NO DISPONIBLE: módulo intel"; fi
  } > "$out"
'
for f in "$TMP_DIR"/node-*.out; do cat "$f"; done
rm -rf "$TMP_DIR"
