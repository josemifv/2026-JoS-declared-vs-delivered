#!/usr/bin/env bash
# launch/20261006-L4-cuda-osu.sh — Prueba funcional CUDA (D5)
#
# Objetivo:     ANTES de omitir OSU device-to-device en GPU: compilar OSU con CUDA
#               contra openmpi_gcc/5.0.5_cuda12 + cuda/12.9.1 y ejecutar
#               osu_bw -d cuda D D entre DOS GPU de un nodo volta. Un job.
# Autorización: DEVIATIONS 2026-10-06 D5 (revisa E51); E51 (2026-10-04) condiciona la
#               omisión de OSU GPU a esta prueba.
# Scripts:      experiments/ligero_gpu_osu_cuda.sbatch — commit 76a7d8091ebb0518ce57dcb673534211f434fa95
# Estimación:   1 job de 1 nodo volta (--gres=gpu:4) × 00:30:00 (compilación ~5-10 min
#               + prueba ~1 min).
# Humo (QA a-h): NO requiere humo previo: ES una prueba funcional (D5), no una medida;
#               registra salida y error si falla (exit real; QA d ✓ por diseño). El
#               build por pila es práctica verificada (R14.4, compile_osu job 83139).
#               El resultado decide: (a) falla → discrepancia declarado/real demostrada;
#               (b) funciona → se añade OSU GPU por partición (nuevo fichero launch/).
# Dependencias: sin dependencias; corre EN PARALELO con cpu112c y cpu36c (partición volta).
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261006-L4-cuda-osu.sh
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"
cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="76a7d8091ebb0518ce57dcb673534211f434fa95"
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
[ "$ACTUAL" = "$EXPECTED_COMMIT" ] || { echo "!! .deploy-commit ($ACTUAL) != commit de los scripts ($EXPECTED_COMMIT)" >&2; exit 2; }
mkdir -p data/raw/ligero

J="$(sbatch --parsable --nodes=1 --partition=volta --gres=gpu:4 --time=00:30:00 \
      experiments/ligero_gpu_osu_cuda.sbatch)"
echo "L4 OSU-CUDA lanzado: job=$J"
