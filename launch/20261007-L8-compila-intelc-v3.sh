#!/usr/bin/env bash
# launch/20261007-L8-compila-intelc-v3.sh — compilación y humo de la pila intelc (T12/T13, D21)
# v3: tolera el cp sobre sí mismo del configure de HPCG (84182); solo spr
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
#               libimf + libintlc; el runtime Fortran de ifx va enlazado
#               estáticamente por defecto; libmpi.so.12 en todos) y sha256
#               por binario, y (5) humo EN EL MISMO JOB con la forma de la
#               celda de 1 nodo de la fase B para intel/mlx.
# Autorización: DEVIATIONS 2026-10-06 D21 (pila intelc; alcance 1: binarios);
#               tarea T12 de TASKS.md. Sin rutas /home/ literales en el sbatch.
# Scripts (sha256 en el commit de referencia; regla 9):
#   experiments/helpers/compile_intelc.sbatch 0d45e47bd68c777f3d27db7f1c9075c1cf055f9a933eb78021880cc3da43d6a4
# Commit de referencia: 34179e1c02298c7a99e0213bf9c5d737af132274 (el commit que
#               contiene ESTE sha256 del script; la puerta de abajo comprueba el
#               sha256 del script DESPLEGADO; la desalineación del .deploy-commit,
#               si la hubiera, se declara con AVISO).
# Nodos fijos:  spr → 1 nodo de cpu112c con --exclude=b9p02,b9p12 (nodos SMT-on
#               excluidos, los mismos de las cadenas de 8 nodos de fase B);
#               clx → 1 nodo del grupo SMT-off de cpu36c (aac102, el
#               representante de los humos c36-off de L7a).
# Estimación:   1 job de 1 nodo × 01:30:00 (sonda + 4 makes NPB +
#               HPCG ~10-15 min solo en spr + humo: 4 runs NPB clase D
#               (ft ~195 s, ep ~45-60 s, cg ~2-5 min, mg ~1-3 min según calib36
#               y la matriz) + HPCG 104³/60 s solo spr).
# Runs esperados en el humo: spr 5 (ft, ep, cg, mg + xhpcg); clx NO va en
#               esta v3 (lo lleva la v2: job 84183, COMPLETED 0:0). NO es una
#               medida del estudio: es la
#               preparación y verificación de los binarios intelc (T13 los
#               usará); los datos del humo quedan en data/raw/intelc/ y scratch.
# Dependencias: ninguna obligatoria (jobs de 1 nodo); DEPENDE_DE=<jobid> añade
#               -d afterany al PRIMER sbatch (spr) si se desea encadenar.
# Aprobación:   PENDIENTE de la persona por el sha256 de ESTE fichero (anotado
#               en informes/estado-lineas.md): el agente NO lo ejecuta sin ella.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261007-L8-compila-intelc-v3.sh
set -euo pipefail
REPO="${TURGALIUM_REPO:-$HOME/cc2026/repo}"
cd "$REPO" || exit 1
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $REPO" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="34179e1c02298c7a99e0213bf9c5d737af132274"
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
check_sha experiments/helpers/compile_intelc.sbatch 0d45e47bd68c777f3d27db7f1c9075c1cf055f9a933eb78021880cc3da43d6a4
mkdir -p data/raw/intelc

DEP="${DEPENDE_DE:-}"
DEPOPT=""
[ -n "$DEP" ] && DEPOPT="-d afterany:$DEP"

# spr: cpu112c, sin los nodos SMT-on (b9p02, b9p12); clx NO va en esta v3
#      (su humo lo llevó la v2: job 84183, COMPLETED 0:0)
S="$(sbatch --parsable $DEPOPT -p cpu112c --exclude=b9p02,b9p12 --time=01:30:00 \
      experiments/helpers/compile_intelc.sbatch spr)"
echo "L8-v3 compilación intelc lanzada: spr=$S (clx: 84183, v2)"
