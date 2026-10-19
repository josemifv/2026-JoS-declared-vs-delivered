#!/usr/bin/env bash
# launch/20261008-L9a-humo-faseB-intelc.sh — humo T14/D21, no lanzar sin firma
# Objetivo: una ronda real de cada carga y talla que medirá L9b: EP+FT, CG y MG a
# 1/2/4/8 nodos, y HPCG a 8 nodos. Cada línea conserva la forma de su asignación.
# Autorización: D21 (TASKS.md, 2026-10-06); T14. STREAM queda fuera por D20.
# Script: experiments/fase_b_intelc.sh; la puerta comprueba su SHA-256.
# Commit de contenido de scripts: 44fcdfbac6ad1bc43d74d56d6a0932c14c59721a.
# Base: fase B 83717-83725 (c1f5b263..., 94966c95...). 13 jobs, 1 ronda cada uno.
# Esperados: EP+FT = 4×4 = 16; CG = 2×4 = 8; MG = 2×4 = 8; HPCG-8n = 2;
# total 34 runs válidos, más controles y map-checks.
# Reserva: 13 jobs × 00:30:00; 53 nodos en total, 26,5 nodo-hora.
# Aprobación: PENDIENTE de la persona por SHA-256 de este fichero.
set -euo pipefail
REPO="${TURGALIUM_REPO:-$HOME/cc2026/repo}"; cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }; source clusters/local.env
check_sha() { local real; real="$(sha256sum experiments/fase_b_intelc.sh | awk '{print $1}')"; [ "$real" = "$1" ] || { echo "!! sha256 NO coincide: $real" >&2; exit 4; }; echo "sha256 OK: experiments/fase_b_intelc.sh"; }
check_sha e23dd72335325bf59ada8f0acdec0fbd16fb28edfbf406738f1a0bbb89d80d37
sbatch --parsable --nodes=1 --exclude=b9p02,b9p12 --time=00:30:00 experiments/fase_b_intelc.sh ep_ft 1 1
sbatch --parsable --nodes=2 --exclude=b9p02,b9p12 --time=00:30:00 experiments/fase_b_intelc.sh ep_ft 1 1
sbatch --parsable --nodes=4 --exclude=b9p02,b9p12 --time=00:30:00 experiments/fase_b_intelc.sh ep_ft 1 1
sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=00:30:00 experiments/fase_b_intelc.sh ep_ft 1 1
sbatch --parsable --nodes=1 --exclude=b9p02,b9p12 --time=00:30:00 experiments/fase_b_intelc.sh cg 1 1
sbatch --parsable --nodes=2 --exclude=b9p02,b9p12 --time=00:30:00 experiments/fase_b_intelc.sh cg 1 1
sbatch --parsable --nodes=4 --exclude=b9p02,b9p12 --time=00:30:00 experiments/fase_b_intelc.sh cg 1 1
sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=00:30:00 experiments/fase_b_intelc.sh cg 1 1
sbatch --parsable --nodes=1 --exclude=b9p02,b9p12 --time=00:30:00 experiments/fase_b_intelc.sh mg 1 1
sbatch --parsable --nodes=2 --exclude=b9p02,b9p12 --time=00:30:00 experiments/fase_b_intelc.sh mg 1 1
sbatch --parsable --nodes=4 --exclude=b9p02,b9p12 --time=00:30:00 experiments/fase_b_intelc.sh mg 1 1
sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=00:30:00 experiments/fase_b_intelc.sh mg 1 1
sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=00:30:00 experiments/fase_b_intelc.sh hpcg 1 1
