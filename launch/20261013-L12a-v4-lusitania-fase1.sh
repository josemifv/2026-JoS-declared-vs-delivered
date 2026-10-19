#!/usr/bin/env bash
# T46 — L12a-v4: Lusitania; compilación, verificación y calibración con dependencias.
# Orden: informes/ordenes/2026-10-14-T46-escalada-3.md; correcciones de T40/T44.
# Jobs: compila 1 × 01:00 (1 nodo-h); verif 2 × 01:00 (2 nodo-h); calib 8 × 00:45 (6 nodo-h); 3 jobs, 9 nodo-h.
# Cuenta del tiempo de verificación: 120 s por prueba más 10 s de margen = 130 s en el peor caso; caben 27 pruebas en 01:00:00; Xula enumeró 10 en 2734471.
# Runs esperados: calibración 4 (2 pilas × clases C y D); verificación una fila por transporte que enumeren ucx_info -d y fi_info en el job; en Lusitania, sin enumeración previa.
# Commit de scripts: 78b77510; no lanzar sin firma.
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
check_sha(){ local actual; actual="$(sha256sum "$1" | awk '{print $1}')"; [ "$actual" = "$2" ] || { printf 'sha256 MAL: %s\n' "$1" >&2; exit 4; }; printf 'sha256 OK: %s\n' "$1"; }
check_sha clusters/perfiles/lusitania.env c40176d295de27add5eb02f42c0d9b4706dab36ad9fd6211ad5fd4fa8b474196
check_sha experiments/portable/perfil.sh 722752beff83e18098988bbde754dfd5905feb8f93d00f5f70c1555c22fb1d67
check_sha experiments/portable/fase1.sh e3da16448c5f725b26a8f76da6e379bd3527f8d0800facc98dd3518b801f740b
check_sha experiments/portable/compila.sbatch b3afdcfbf559c6ca122171d9a774a9a55e82a6a699c6324100857908ac29feb3
check_sha experiments/portable/verif.sbatch a98d055c71db738797a813130b27b18c1822bd7d8bc92f70fbc048a637b23136
check_sha experiments/portable/calib.sbatch 10737a3fcae7ab1f63b2759b39a9247b502bb5cade85fd91be3e41c82fab19d0
check_sha instrumentation/cmdlog.sh 24077987874075fd47df1c3f44626265665ad25153da2928a2a2438753767c63
export PERFIL=clusters/perfiles/lusitania.env SIN_DESCUBRIMIENTO=1
bash experiments/portable/fase1.sh
