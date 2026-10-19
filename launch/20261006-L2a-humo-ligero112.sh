#!/usr/bin/env bash
# launch/20261006-L2a-humo-ligero112.sh — HUMO del protocolo ligero INDEPENDIENTE
# de cpu112c (D18): verificación funcional + 1 ronda de colectivas OSU + 1 ronda de FT-8n.
#
# Objetivo:     QA a-h del ligero112 antes de L2b/L2c: verificación de los 7 combos
#               (probe exit 0 + transporte observado = pedido + map-check 64 r/n +
#               ldd), humo de colectivas (1 ronda, 512 ranks) y humo de FT-8n
#               (1 ronda, 4 pares candidatos de la R2 de la matriz).
# Autorización: DEVIATIONS 2026-10-06 D18 (repetición independiente de E-f); QA
#               permanente a-g de AGENTS.md.
# Scripts:      experiments/ligero112_verif.sbatch, ligero112_osu.sbatch,
#               ligero112_ft8n.sbatch, helpers/ligero36_pin.sh — commit
#               76a7d8091ebb0518ce57dcb673534211f434fa95
# Estimación:   3 jobs: verif 2 nodos 00:30:00; coll humo 8 nodos 01:00:00 (1 ronda
#               de 7 pares × allreduce+alltoall ≈ 30 min); ft8n humo 8 nodos
#               01:00:00 (4 pares × ~20 s).
# Humo:         ESTE fichero ES el humo (L2a); sin humo previo de estos scripts
#               adaptados. QA esperada tras su ejecución: a) asignación misma
#               forma/tamaño que la medida (pt2pt 2n la cubre verif; coll y ft8n
#               8n×512r); b) map-check 64r/n + ldd por combo/celda + transporte
#               observado = pedido; c) patrón de éxito (# OSU MPI / SUCCESSFUL +
#               Size D) contra salida real — el caso que debe fallar (ft.B.x vs
#               patrón clase D) ya probado contra salida real (calib36-83379, FALLO ✓);
#               d) exit_code real por run en manifiesto; e) parámetros trazados a
#               D18/E-f/R1/P-2/P-5; f) salida a la persona antes de L2b; g) sync +
#               verifica_raw tras cada job; h) este fichero y su sha256 al panel.
# Dependencias: después de L1 (propuesta de orden; sin dependencia técnica). L2b se
#               lanza tras revisar la salida de ESTE humo.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261006-L2a-humo-ligero112.sh
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"
cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="76a7d8091ebb0518ce57dcb673534211f434fa95"
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
[ "$ACTUAL" = "$EXPECTED_COMMIT" ] || { echo "!! .deploy-commit ($ACTUAL) != commit de los scripts ($EXPECTED_COMMIT)" >&2; exit 2; }
mkdir -p data/raw/ligero112

# 1) verificación funcional de los 7 combos (2 nodos SMT-off: el par pt2pt de L2b)
V="$(sbatch --parsable --nodelist=b9p03,b9p04 --time=00:30:00 experiments/ligero112_verif.sbatch)"
# 2) humo de colectivas: 1 ronda (tras el verif; el job salta combos sin OK)
C="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=01:00:00 -d afterok:$V \
      experiments/ligero112_osu.sbatch coll 1 1)"
# 3) humo de FT-8n: 1 ronda con los 4 pares candidatos (R2 de la matriz)
F="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=01:00:00 -d afterany:$C \
      experiments/ligero112_ft8n.sbatch 1 1 "gcc rc" "intel mlx" "gcc dc" "intel verbs;ofi_rxm")"
echo "L2a humo ligero112 lanzado: verif=$V coll=$C ft8n=$F (final=$F)"
