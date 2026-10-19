#!/usr/bin/env bash
# launch/20261006-L4-cuda-osu-v2.sh — Prueba funcional CUDA (D5)
#
# QUÉ CAMBIA RESPECTO A v1 (Prompt C 7): (1) verificación del sha256 desplegado del
# script antes del sbatch — aborta exit 4 (regla 9, QA h); (2) DEPENDE_DE; (3) el
# script v2 (694db2c7…) corrige el lanzamiento (-ppn → --map-by ppr:2:node, Prompt C
# 5.1), verifica en config.log que CUDA quedó activado (Prompt C 5.2) y añade los
# controles ompi_info/ucx_info/osu_bw H H con la clasificación INVALIDA /
# CUDA-NO-FUNCIONAL (Prompt C 5.3).
# Objetivo:     ANTES de omitir OSU device-to-device en GPU: compilar OSU con CUDA
#               contra openmpi_gcc/5.0.5_cuda12 + cuda/12.9.1 y ejecutar
#               osu_bw -d cuda D D entre DOS GPU de un nodo volta. Un job.
# Autorización: DEVIATIONS 2026-10-06 D5 (revisa E51).
# Scripts (sha256 en el commit de referencia; regla 9):
#   experiments/ligero_gpu_osu_cuda.sbatch 694db2c7e13fab036182b0c28d25f3c792a0718cd6f7972823306e5afcdb2fdf
# Nodos fijos:   ninguno (1 nodo cualquiera de volta con --gres=gpu:4). b9p03 NO
#               interviene (partición volta).
# Estimación:   1 job de 1 nodo volta × 00:30:00 (compilación ~5-10 min + prueba ~1 min).
# Humo (QA a-h): NO requiere humo previo: ES una prueba funcional (D5), no una
#               medida; registra salida y error si falla; exit real registrado
#               (QA d/f ✓ por diseño). El resultado decide: (a) falla → discrepancia
#               declarado/real demostrada; (b) funciona → se añade OSU GPU por
#               partición (nuevo fichero launch/).
# Dependencias: sin dependencias; corre EN PARALELO con cpu112c y cpu36c (volta).
# sha256 de ESTE fichero: anotado en informes/estado-lineas.md.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261006-L4-cuda-osu-v2.sh
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"
cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="701ec01fb042a7c9361fd884af423ae101fe421f"
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
check_sha experiments/ligero_gpu_osu_cuda.sbatch 694db2c7e13fab036182b0c28d25f3c792a0718cd6f7972823306e5afcdb2fdf
mkdir -p data/raw/ligero

DEP="${DEPENDE_DE:-}"
DEPOPT=""
[ -n "$DEP" ] && DEPOPT="-d afterany:$DEP"

J="$(sbatch --parsable $DEPOPT --nodes=1 --partition=volta --gres=gpu:4 --time=00:30:00 \
      experiments/ligero_gpu_osu_cuda.sbatch)"
echo "L4-v2 OSU-CUDA lanzado: job=$J"
