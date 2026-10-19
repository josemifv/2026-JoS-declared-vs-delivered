#!/usr/bin/env bash
# T50 — L16: Lusitania us63; compilación, verificación y calibración con dependencias.
# Orden: informes/ordenes/2026-10-15-T50-lusitania-us63.md (sha256 2bc90e65…);
# DEVIATIONS 2026-10-15 us63. Deriva de launch/20261013-L12a-v4-lusitania-fase1.sh
# cambiando solo el perfil (us63) y la variante fase1-us63.sh (kill-on-invalid-dep).
# Jobs: compila 1 × 01:00 (1 nodo-h); verif 2 × 01:00 (2 nodo-h); calib 8 × 00:45 (6 nodo-h); 3 jobs, 9 nodo-h, dentro del máximo de 20.
# La compilación hace de primera puerta: verificación y calibración dependen de ella
# con afterok y se eliminan si falla (--kill-on-invalid-dep=yes), como en las cadenas anteriores.
# Cuenta del tiempo de verificación: 120 s por prueba más 10 s de margen = 130 s en el peor caso; caben 27 pruebas en 01:00:00.
# Runs esperados: calibración 4 (2 pilas × clases C y D); verificación una fila por transporte que enumeren ucx_info -d y fi_info en el job; en us63, sin enumeración previa.
# Duración esperada: ~2 h de ejecución (compila 1 h; después verif 1 h y calib 45 min en paralelo) más la espera de cola.
# Sin descubrimiento de us63 en esta cadena (SIN_DESCUBRIMIENTO=1, como la v4); el tope de 20 nodo-h excluye los 52 jobs de 20 min (~17,3 nodo-h más).
# Commit de scripts: 3b0e33307611e2b07bbdf5c30a6a22a4b07b4c60; no lanzar sin firma.
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
check_sha clusters/perfiles/lusitania-us63.env d7a3c72a19c7cea65a771ad9b02a96141f72ab01a6e3b3472f73c9c18d7d48cf
check_sha experiments/portable/perfil.sh 722752beff83e18098988bbde754dfd5905feb8f93d00f5f70c1555c22fb1d67
check_sha experiments/portable/fase1-us63.sh 400d58b7ccc37b1335c8d05d39d79778bde74b416d1b59357792e92271bc35ca
check_sha experiments/portable/compila.sbatch b3afdcfbf559c6ca122171d9a774a9a55e82a6a699c6324100857908ac29feb3
check_sha experiments/portable/verif.sbatch a98d055c71db738797a813130b27b18c1822bd7d8bc92f70fbc048a637b23136
check_sha experiments/portable/calib.sbatch 10737a3fcae7ab1f63b2759b39a9247b502bb5cade85fd91be3e41c82fab19d0
check_sha instrumentation/cmdlog.sh 24077987874075fd47df1c3f44626265665ad25153da2928a2a2438753767c63
export PERFIL=clusters/perfiles/lusitania-us63.env SIN_DESCUBRIMIENTO=1
bash experiments/portable/fase1-us63.sh
