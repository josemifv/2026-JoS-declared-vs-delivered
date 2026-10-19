#!/usr/bin/env bash
# T46 — L11a-v4: Xula xula4; verificación y calibración a 2 nodos, sin discovery ni compilación.
# Orden: informes/ordenes/2026-10-14-T46-escalada-3.md; scripts de T46 y T44.
# Jobs: verif 2 nodos × 01:00 (2 nodo-h); calib 2 nodos × 00:45 (1,5 nodo-h); 2 jobs, 3,5 nodo-h.
# Cuenta del tiempo de verificación: 120 s por prueba más 10 s de margen = 130 s en el peor caso; caben 27 pruebas en 01:00:00; Xula enumeró 10 en 2734471.
# Runs esperados: calibración 4 (2 pilas × clases C y D); verificación una fila por transporte que enumeren ucx_info -d y fi_info en el job; en Xula, 10 en la verificación 2734471.
# Commit de scripts: 78b77510; no lanzar sin firma.
set -euo pipefail
if [ "${PORTABLE_REMOTE:-0}" != 1 ]; then
  LAUNCH_FILE="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  cd "$(dirname "$LAUNCH_FILE")/.."
  if [ "${DRY_RUN:-0}" != 1 ]; then
    [ -f clusters/local.env ] || { printf 'falta local.env\n' >&2; exit 2; }
    source clusters/local.env
    : "${XULA_REPO:?falta XULA_REPO}"
    { printf 'cd %q\nexport PORTABLE_REMOTE=1\n' "$XULA_REPO"; cat "$LAUNCH_FILE"; } | ssh xula 'bash -s'
    exit "$?"
  fi
fi
check_sha(){ local actual; actual="$(sha256sum "$1" | awk '{print $1}')"; [ "$actual" = "$2" ] || { printf 'sha256 MAL: %s\n' "$1" >&2; exit 4; }; printf 'sha256 OK: %s\n' "$1"; }
check_sha clusters/perfiles/xula4.env 07324486a8be1bcc4aeaf12e8e60924ed7518751b36e551620aba2a47e6ef99e
check_sha experiments/portable/perfil.sh 722752beff83e18098988bbde754dfd5905feb8f93d00f5f70c1555c22fb1d67
check_sha experiments/portable/fase1.sh e3da16448c5f725b26a8f76da6e379bd3527f8d0800facc98dd3518b801f740b
check_sha experiments/portable/verif.sbatch a98d055c71db738797a813130b27b18c1822bd7d8bc92f70fbc048a637b23136
check_sha experiments/portable/calib.sbatch 10737a3fcae7ab1f63b2759b39a9247b502bb5cade85fd91be3e41c82fab19d0
check_sha instrumentation/cmdlog.sh 24077987874075fd47df1c3f44626265665ad25153da2928a2a2438753767c63
export PERFIL=clusters/perfiles/xula4.env SIN_DESCUBRIMIENTO=1 SIN_COMPILACION=1
bash experiments/portable/fase1.sh
