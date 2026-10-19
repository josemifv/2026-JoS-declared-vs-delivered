#!/usr/bin/env bash
# launch/20261007-L8-compila-intelc.sh — compilación y humo de la pila intelc (T12, D21)
#
# Objetivo:     un job de compilación+humo por arquitectura que (1) sondea los
#               compiladores Intel (ifx, icx, icpx, mpiifx, mpiicx, mpiicpx;
#               sin ifx o sin mpiifx → SIN-IFX, exit 10, sin compilar nada),
#               (2) compila NPB 3.4.1 ft/ep/cg/mg CLASE D con mpiifx
#               (FFLAGS=-O3 -march=<arch>, sin los flags de gfortran; si ifx
#               no acepta -march, el job aborta con el log y NO se prueban
#               flags alternativos) → benchmarks/npb/intelc/<arch>/,
#               (3) en spr, HPCG 3.1.0 con mpiicpx (-DHPCG_NO_OPENMP -O3
#               -march=sapphirerapids, los flags de la fase B) →
#               benchmarks/phaseB/hpcg/intelc/xhpcg, (4) registra ldd (ifx:
#               libifcore/libifport + libimf; libmpi.so.12 en todos) y sha256
#               por binario, y (5) humo EN EL MISMO JOB con la forma de la
#               celda de 1 nodo de la fase B para intel/mlx.
# Autorización: DEVIATIONS 2026-10-06 D21 (pila intelc; alcance 1: binarios);
#               tarea T12 de TASKS.md. Sin rutas /home/ literales en el sbatch.
# Scripts (sha256 en el commit de referencia; regla 9):
#   experiments/helpers/compile_intelc.sbatch 309fe74eebdbb88744b528406e401dbfd78a54e8f732f21f89b7dc45d608e61e
# Commit de referencia: e4de0fa08f56584966b09e699e0c842a5207e5fa (el commit que
#               contiene ESTE sha256 del script; la puerta de abajo comprueba el
#               sha256 del script DESPLEGADO; la desalineación del .deploy-commit,
#               si la hubiera, se declara con AVISO).
# Nodos fijos:  spr → 1 nodo de cpu112c con --exclude=b9p02,b9p12 (nodos SMT-on
#               excluidos, los mismos de las cadenas de 8 nodos de fase B);
#               clx → 1 nodo del grupo SMT-off de cpu36c (aac102, el
#               representante de los humos c36-off de L7a).
# Estimación:   2 jobs de 1 nodo × 01:30:00 cada uno (sonda + 4 makes NPB +
#               HPCG ~10-15 min solo en spr + humo: 4 runs NPB clase D
#               (ft ~195 s, ep ~45-60 s, cg ~2-5 min, mg ~1-3 min según calib36
#               y la matriz) + HPCG 104³/60 s solo spr).
# Runs esperados en el humo: spr 5 (ft, ep, cg, mg + xhpcg); clx 4 (ft, ep,
#               cg, mg). Ningún otro run. NO es una medida del estudio: es la
#               preparación y verificación de los binarios intelc (T13 los
#               usará); los datos del humo quedan en data/raw/intelc/ y scratch.
# Dependencias: ninguna obligatoria (jobs de 1 nodo); DEPENDE_DE=<jobid> añade
#               -d afterany al PRIMER sbatch (spr) si se desea encadenar.
# Aprobación:   PENDIENTE de la persona por el sha256 de ESTE fichero (anotado
#               en informes/estado-lineas.md): el agente NO lo ejecuta sin ella.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261007-L8-compila-intelc.sh
set -euo pipefail
REPO="${TURGALIUM_REPO:-$HOME/cc2026/repo}"
cd "$REPO" || exit 1
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $REPO" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="e4de0fa08f56584966b09e699e0c842a5207e5fa"
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
if [ "$ACTUAL" != "$EXPECTED_COMMIT" ]; then
  echo "AVISO: .deploy-commit ($ACTUAL) != commit de referencia ($EXPECTED_COMMIT); rige el sha256 individual"
fi
check_sha() { # $1 = ruta; $2 = sha256 esperado (regla 9 / QA h) → exit 4 sin lanzar
  local real
  real="$(sha256sum "$1" | awk '{print $1}')"
  if [ "$real" != "$2" ]; then
    echo "!! sha256 desplegado de $1 NO coincide (esperado $2, real $real)" >&2
    exit 4
  fi
  echo "sha256 OK: $1"
}
check_sha experiments/helpers/compile_intelc.sbatch 309fe74eebdbb88744b528406e401dbfd78a54e8f732f21f89b7dc45d608e61e
mkdir -p data/raw/intelc

DEP="${DEPENDE_DE:-}"
DEPOPT=""
[ -n "$DEP" ] && DEPOPT="-d afterany:$DEP"

# spr: cpu112c, sin los nodos SMT-on (b9p02, b9p12)
S="$(sbatch --parsable $DEPOPT -p cpu112c --exclude=b9p02,b9p12 --time=01:30:00 \
      experiments/helpers/compile_intelc.sbatch spr)"
# clx: cpu36c, grupo SMT-off (representante aac102)
C="$(sbatch --parsable -p cpu36c --nodelist=aac102 --time=01:30:00 \
      experiments/helpers/compile_intelc.sbatch clx)"
echo "L8 compilación intelc lanzada: spr=$S clx=$C"
