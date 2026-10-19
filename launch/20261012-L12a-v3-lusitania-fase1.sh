#!/usr/bin/env bash
# T44 — L12a-v3: fase 1 en Lusitania, sin descubrimiento; no lanzar sin firma.
# Orden: informes/ordenes/2026-10-12-T44-portable-v3.md. Corrige parser UCX, compilación limpia,
# flags Fortran por compilador y tests de T40; copia funcional de L12a-v2.
# Jobs: compila 1 + verif 1 + calib 1 = 3 jobs, 8 nodo-h reservadas. Las reservas pendientes
# de Lusitania suman descubrimientos de L12a aún en cola (31 × 20 min) más sus 8 nodo-h.
# DRY_RUN=1 para comprobar puertas; este fichero no se ejecuta durante T44.
set -euo pipefail
if [ "${PORTABLE_REMOTE:-0}" != 1 ]; then
    LAUNCH_FILE="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    cd "$(dirname "$LAUNCH_FILE")/.."
    if [ "${DRY_RUN:-0}" != 1 ]; then
        [ -f clusters/local.env ] || { printf 'falta local.env\n' >&2; exit 2; }
        source clusters/local.env
        : "${LUSITANIA_REPO:?falta LUSITANIA_REPO}"
        { printf 'cd %q\nexport PORTABLE_REMOTE=1\n' "$LUSITANIA_REPO"; cat "$LAUNCH_FILE"; } | ssh computaex 'bash -s'
        exit "$?"
    fi
fi
check_sha() { local actual; actual="$(sha256sum "$1" | awk '{print $1}')"; [ "$actual" = "$2" ] || { printf 'sha256 MAL: %s\n' "$1" >&2; exit 4; }; printf 'sha256 OK: %s\n' "$1"; }
check_sha clusters/perfiles/lusitania.env dc201d4e5bad19690c9815c85679a0de70d964ccb070bbb743050155c36dd73b
check_sha experiments/portable/perfil.sh 0b162957126827abfd3754173dd9853856f1c9fc05f418a1c23c5c53d870ae51
check_sha experiments/portable/fase1.sh 867c1b886252a67151a694fdc3fa26433b5db0a4e5ee9c04bad53bfe0fd7f242
check_sha experiments/portable/compila.sbatch b3afdcfbf559c6ca122171d9a774a9a55e82a6a699c6324100857908ac29feb3
check_sha experiments/portable/verif.sbatch bad1cbd6b5bb4864e92cb700605d854cab73454e93555178a1546f1a529438c2
check_sha experiments/portable/calib.sbatch dc062bd91aa12df8974522de663b9d7be04b6ef98cf3ec514335c8ea7fe8489d
check_sha experiments/portable/pin.sh 0874457ed4d699a897af9d292c489b353f99fab028d9f5402f35b8524cc7b355
check_sha experiments/portable/observa.py 79826bb6d3ff9cbe2997d310b55865ddf0c0986cb947906ad09e4baff9945f40
check_sha discovery/run_discovery.sh a461371c0d4c6fe112a02c0d354a44fd4eea00429c848700b0ce9dc4920be2e0
check_sha discovery/collect_node.py 2c743b218d8ccbd6dd7789de6b48391c4176462f16776ab2608e5ebe4477b345
check_sha instrumentation/cmdlog.sh 24077987874075fd47df1c3f44626265665ad25153da2928a2a2438753767c63
export PERFIL=clusters/perfiles/lusitania.env
export SIN_DESCUBRIMIENTO=1
bash experiments/portable/fase1.sh
