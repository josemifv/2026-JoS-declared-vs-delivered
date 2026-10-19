#!/usr/bin/env bash
# launch/20261006-L6-anclas-v2.sh — Anclas del antes/después: SOLO HPCG, UNA sesión
#
# QUÉ CAMBIA RESPECTO A v1 (Prompt C 7): (1) verificación del sha256 desplegado del
# script antes del sbatch — aborta exit 4 (regla 9, QA h); (2) DEPENDE_DE para el
# encadenado por la persona (L1 → L5 → L6 → L2a); (3) cabecera con nodos fijos.
# Objetivo:     11 rondas intercaladas entre las celdas cmmse y actual (1 calentamiento
#               + 10 efectivas por stack), 4 celdas por ronda (cmmse/actual × gcc/intel),
#               configuración CMMSE verbatim (104³ local, 60 s de ejecución, 448 ranks
#               = 8×56/nodo), control D-B al inicio y fin, 8 nodos SMT-off, nivel 1
#               unprivileged, map-check por celda, verificación por el txt del rundir.
# Autorización: DEVIATIONS 2026-10-05 (E69: HPL fuera, R6 desactivada, una sesión;
#               E68 parcial); D4 (2026-10-06: cmmse-gcc sin el módulo gcc/11.2.0).
# Scripts (sha256 en el commit de referencia; regla 9):
#   experiments/anchors_hpcg_hpl.sh 4460866ff2a11d37765b471c6dcb27ad0b42c8a98f98c0b577df7c53189f7e7f
# Nodos fijos:   ninguno propio (8 cualesquiera SMT-off, --exclude=b9p02,b9p12;
#               no-identidad R4.5 declarada al lanzar). NOTA: puede compartir nodos
#               con L2/L5/L7 en asignaciones distintas (--exclusive evita solape).
# Estimación:   1 job de 8 nodos × 03:00:00 (44 runs × ~2,4 min ≈ 1,8 h + controles).
# Humo (QA a-h): 83799 (v2; 1 ronda) — COMPLETED; v1 83737 falló al cargar gcc/11.2.0
#               (módulo desaparecido) y la v2 carga SOLO openmpi_gcc/5.0.5 con el
#               LD_LIBRARY_PATH del OpenBLAS del CMMSE; exit real, ldd por celda,
#               transporte efectivo observado, hpcg.dat del CMMSE obligatorio con sha
#               por run, regex GFLOP/s probada contra salida real; sincronizado y
#               verificado. QA: a✓ b✓ c✓ d✓ e✓ f✓ g✓ h✓ (este fichero).
# Dependencias: propuesta: ÚLTIMA de la serie de 8 nodos (L1 → L5 → L6 → L2a; L2b/L2c
#               de 8 nodos después, o L6 al final según lo encadene la persona con
#               DEPENDE_DE).
# sha256 de ESTE fichero: anotado en informes/estado-lineas.md.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261006-L6-anclas-v2.sh
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
check_sha experiments/anchors_hpcg_hpl.sh 4460866ff2a11d37765b471c6dcb27ad0b42c8a98f98c0b577df7c53189f7e7f
mkdir -p data/raw/anchors

DEP="${DEPENDE_DE:-}"
DEPOPT=""
[ -n "$DEP" ] && DEPOPT="-d afterany:$DEP"

J="$(sbatch --parsable $DEPOPT --nodes=8 --exclude=b9p02,b9p12 --time=03:00:00 \
      experiments/anchors_hpcg_hpl.sh)"
echo "L6-v2 anclas HPCG lanzado: job=$J (una sesión, 11 rondas intercaladas)"
