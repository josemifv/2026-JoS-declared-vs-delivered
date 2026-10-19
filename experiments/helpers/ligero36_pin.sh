#!/usr/bin/env bash
# Emplazamiento pt2pt (DEVIATIONS 2026-10-03): el único rank de cada nodo se fija
# al primer core del dominio NUMA local al HCA, el mismo core en ambas pilas.
# El dominio se lee de sysfs sin privilegios; si no es observable (R14.3), se
# declara y se usa NUMA node0 (CPU 0). Mecanismo: taskset envolvente
# (I_MPI_PIN=0 en Intel MPI, --bind-to none en Open MPI) — distinto del de la
# fase A (binding del runtime a CPU 0) pero misma regla de emplazamiento
# (DEVIATIONS 2026-10-04). El pedido y el real quedan en el run.log (R10).
# Uso (dentro de mpirun, se ejecuta EN cada nodo): bash ligero36_pin.sh <binario> [args...]
set -euo pipefail
CORE=0
nd="$(cat /sys/class/infiniband/*/device/numa_node 2>/dev/null | head -1 || true)"
nd="${nd:-}"
if [ -n "$nd" ] && [ "$nd" != "-1" ] && [ -d "/sys/devices/system/node/node$nd" ]; then
    cl="$(cat /sys/devices/system/node/node$nd/cpulist)"
    first="${cl%%-*}"
    first="${first%,*}"
    if [[ "$first" =~ ^[0-9]+$ ]]; then CORE="$first"; fi
    ORIGEN="sysfs(node$nd)"
else
    ORIGEN="fallback(node0)"
fi
echo "pin-pedido: host=$(hostname -s) hca_numa=${nd:-NA} core=$CORE origen=$ORIGEN"
taskset -c "$CORE" bash -c 'echo "pin-real: host=$(hostname -s) cpus=$(taskset -pc $$ | awk "{print \$NF}")"'
exec taskset -c "$CORE" "$@"
