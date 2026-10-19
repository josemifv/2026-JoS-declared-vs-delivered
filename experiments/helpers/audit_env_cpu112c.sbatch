#!/usr/bin/env bash
#SBATCH --job-name=env-audit
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --account=<account>
#SBATCH --time=00:05:00
#SBATCH --output=data/raw/phaseB/env-audit-%j.out
# Línea 2 (anclas): fechas de instalación del stack de sistema en un nodo de
# CÓMPUTO (no login) para acotar la atribución temporal de las anclas del CMMSE
# (orden de la persona, 2026-10-04): kernel, rdma-core, libfabric y firmware del
# HCA. Si algo cambió después de mayo de 2026 (mes de acceso del CMMSE), se
# registra en DEVIATIONS como límite de la atribución; no bloquea.
# Consultas rpm en modo lectura (sin privilegios); firmware vía ibstat (sysfs).
set -uo pipefail
echo "== nodo $(hostname -s) $(date -Is)"
echo "== kernel (últimas instalaciones + versión en ejecución):"
rpm -q --last kernel 2>&1 | head -3
uname -r
cat /proc/version 2>/dev/null | head -1
echo "== rdma-core:"
rpm -q --last rdma-core 2>&1 | head -3
echo "== libfabric:"
rpm -q --last libfabric 2>&1 | head -3
echo "== ucx (rpm y versión real cargable):"
rpm -q --last ucx libucx 2>&1 | head -3
if [ -x /usr/bin/ucx_info ]; then /usr/bin/ucx_info -v 2>&1 | head -2; else echo "(ucx_info no disponible)"; fi
echo "== firmware HCA (ibstat):"
fw_sysfs() {
  for d in /sys/class/infiniband/mlx5_*; do
    [ -d "$d" ] || continue
    fw="$(cat "$d/fw_ver" 2>/dev/null || echo NA)"
    echo "  $(basename "$d") fw_ver=$fw"
  done
}
if command -v ibstat >/dev/null; then
  ibstat 2>/dev/null | grep -iE "CA type|Firmware" | head -6
  ibstat 2>/dev/null | grep -qi Firmware || fw_sysfs
else
  fw_sysfs
fi
echo "== compiladores del sistema:"
gcc --version 2>/dev/null | head -1 || true
gfortran --version 2>/dev/null | head -1 || true
echo "== fin auditoría de entorno (job $SLURM_JOB_ID)"
