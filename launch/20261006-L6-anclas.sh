#!/usr/bin/env bash
# launch/20261006-L6-anclas.sh — Anclas del antes/después: SOLO HPCG, UNA sesión
#
# Objetivo:     11 rondas intercaladas entre las celdas cmmse y actual (1 calentamiento
#               + 10 efectivas por stack), 4 celdas por ronda (cmmse/actual × gcc/intel),
#               configuración CMMSE verbatim (104³ local, 60 s de ejecución, 448 ranks
#               = 8×56/nodo), control D-B al inicio y fin, 8 nodos SMT-off, nivel 1
#               unprivileged, map-check por celda, verificación por el txt del rundir.
# Autorización: DEVIATIONS 2026-10-05 (E69: HPL fuera, R6 desactivada, una sesión;
#               E68 parcial); D4 (2026-10-06: cmmse-gcc sin el módulo gcc/11.2.0).
# Scripts:      experiments/anchors_hpcg_hpl.sh (v2; parte HPL OBSOLETA, no se usa) —
#               commit 76a7d8091ebb0518ce57dcb673534211f434fa95
# Estimación:   1 job de 8 nodos × 03:00:00 (44 runs × ~2,4 min ≈ 1,8 h + controles).
# Humo (QA a-h): 83799 (v2; 1 ronda) — COMPLETED; v1 83737 falló al cargar
#               gcc/11.2.0 (módulo desaparecido del clúster, hallazgo declarado/real)
#               y la v2 carga SOLO openmpi_gcc/5.0.5 con LD_LIBRARY_PATH del OpenBLAS
#               del CMMSE; exit real, ldd por celda (libmpi = la del mpirun), transporte
#               efectivo observado, hpcg.dat del CMMSE obligatorio con sha por run,
#               regex GFLOP/s probada contra salida real; sincronizado y verificado.
#               QA: a✓ (8 nodos, 56 r/n = forma de la medida) b✓ c✓ (VALID/INVALID/
#               NO-VERIFICADO por txt probado contra salida real del humo) d✓ e✓
#               (trazado a E69/E68-parcial/D4/R4/R5.2) f✓ g✓ h (este fichero).
# Dependencias: propuesta: ÚLTIMA de la serie de 8 nodos en cpu112c (L1 → L2a → L2b →
#               L2c → L6); comparte la ventana SMT-off con L1/L2, no en paralelo.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261006-L6-anclas.sh
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"
cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="76a7d8091ebb0518ce57dcb673534211f434fa95"
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
[ "$ACTUAL" = "$EXPECTED_COMMIT" ] || { echo "!! .deploy-commit ($ACTUAL) != commit de los scripts ($EXPECTED_COMMIT)" >&2; exit 2; }
mkdir -p data/raw/anchors

J="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=03:00:00 \
      experiments/anchors_hpcg_hpl.sh)"
echo "L6 anclas HPCG lanzado: job=$J (una sesión, 11 rondas intercaladas)"
