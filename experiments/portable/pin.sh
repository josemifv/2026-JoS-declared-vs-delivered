#!/usr/bin/env bash
# Origen: experiments/helpers/ligero36_pin.sh
# SHA256: 6788d173ae493d8293b87c76fdc156522953407ad9ff5d48eb5601987bde280b
# Misma elección HCA-local/fallback; registra rank y bibliotecas en el proceso.
set -euo pipefail
if [ "${DRY_RUN:-0}" = 1 ]; then
    printf 'pin=primer_core_NUMA_HCA fallback=0 mapa=POR_DETERMINAR\n'
    exit 0
fi
CORE=0
nd="$(cat /sys/class/infiniband/*/device/numa_node 2>/dev/null | head -1 || true)"
if [ -n "$nd" ] && [ "$nd" != -1 ] && [ -d "/sys/devices/system/node/node$nd" ]; then
    cl="$(cat "/sys/devices/system/node/node$nd/cpulist")"
    first="${cl%%-*}"; first="${first%,*}"
    if [[ "$first" =~ ^[0-9]+$ ]]; then CORE="$first"; fi
    ORIGEN="sysfs(node$nd)"
else
    ORIGEN="fallback(node0)"
fi
echo "pin-pedido: host=$(hostname -s) rank=${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-NA}} core=$CORE origen=$ORIGEN"
taskset -c "$CORE" bash -c 'echo "pin-real: host=$(hostname -s) rank=${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-NA}} cpus=$(taskset -pc $$ | awk "{print \$NF}")"'
ldd "$1"
exec taskset -c "$CORE" "$@"
