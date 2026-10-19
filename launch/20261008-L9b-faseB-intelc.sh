#!/usr/bin/env bash
# launch/20261008-L9b-faseB-intelc.sh — medida completa T14/D21, no lanzar sin firma
# Origen de tiempos: NPB 1n/2n/4n de 83717-83725; NPB 8n de las celdas
# de 512 ranks de 83314, 83315, 83316, 83317, 83318, 83405, 83406 y 83407;
# HPCG 8n de 83403. Fórmula: intel/mlx × 2 × 1,3 + 10 min, redondeado a 5 min.
# Decisión de la persona (2026-10-08): 13 jobs, una asignación de 11 rondas
# por carga y talla; con 2 pares no hace falta el troceado por rondas de los 4 pares.
# Cada carga/talla/par produce 11 runs; EP/FT tienen 4 por talla, CG/MG 2 y HPCG 2.
# Total esperado: EP 88 + FT 88 + CG 88 + MG 88 + HPCG 22 = 374 runs válidos.
# Commit de contenido de scripts: 44fcdfbac6ad1bc43d74d56d6a0932c14c59721a.
# Reserva: 30,2 nodo-hora; consumo esperado de unas 14 nodo-hora.
# Autorización: D21/T14 y decisión de la persona (2026-10-08).
# L9b se lanza solo después de revisar L9a y de recibir la firma de la persona.
# si en el humo L9a alguna celda de intelc tarda más de 1,6 veces lo que tarda intel, se recalcula esa línea antes de firmar
# Aprobación: PENDIENTE de la persona por SHA-256 de este fichero.
set -euo pipefail
REPO="${TURGALIUM_REPO:-$HOME/cc2026/repo}"; cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }; source clusters/local.env
check_sha() { local real; real="$(sha256sum experiments/fase_b_intelc.sh | awk '{print $1}')"; [ "$real" = "$1" ] || { echo "!! sha256 NO coincide: $real" >&2; exit 4; }; echo "sha256 OK: experiments/fase_b_intelc.sh"; }
check_sha e23dd72335325bf59ada8f0acdec0fbd16fb28edfbf406738f1a0bbb89d80d37
sbatch --parsable --nodes=1 --exclude=b9p02,b9p12 --time=01:10:00 experiments/fase_b_intelc.sh ep_ft 1 11
sbatch --parsable --nodes=2 --exclude=b9p02,b9p12 --time=00:45:00 experiments/fase_b_intelc.sh ep_ft 1 11
sbatch --parsable --nodes=4 --exclude=b9p02,b9p12 --time=00:35:00 experiments/fase_b_intelc.sh ep_ft 1 11
sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=00:25:00 experiments/fase_b_intelc.sh ep_ft 1 11
sbatch --parsable --nodes=1 --exclude=b9p02,b9p12 --time=00:50:00 experiments/fase_b_intelc.sh cg 1 11
sbatch --parsable --nodes=2 --exclude=b9p02,b9p12 --time=00:30:00 experiments/fase_b_intelc.sh cg 1 11
sbatch --parsable --nodes=4 --exclude=b9p02,b9p12 --time=00:25:00 experiments/fase_b_intelc.sh cg 1 11
sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=00:20:00 experiments/fase_b_intelc.sh cg 1 11
sbatch --parsable --nodes=1 --exclude=b9p02,b9p12 --time=00:20:00 experiments/fase_b_intelc.sh mg 1 11
sbatch --parsable --nodes=2 --exclude=b9p02,b9p12 --time=00:20:00 experiments/fase_b_intelc.sh mg 1 11
sbatch --parsable --nodes=4 --exclude=b9p02,b9p12 --time=00:20:00 experiments/fase_b_intelc.sh mg 1 11
sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=00:20:00 experiments/fase_b_intelc.sh mg 1 11
sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=01:20:00 experiments/fase_b_intelc.sh hpcg 1 11
