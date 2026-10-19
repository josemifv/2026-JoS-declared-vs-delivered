#!/usr/bin/env bash
# launch/20261009-L10-b9p07.sh — sonda y comparación A/B del efecto de b9p07
# Objetivo: FT-8n y CG-8n con gcc/rc, gcc/dc, gcc/ud, intel/mlx e intelc/mlx.
# Autorización: orden informes/ordenes/2026-10-09-T26-b9p07.md; T26.
# A = b9p06,b9p07,b9p08,b9p09,b9p10,b9p11,b9p13,b9p16; B sustituye b9p07 por b9p14.
# 6 rondas (1 calentamiento + 5 efectivas). Por conjunto y carga: gcc/rc, gcc/dc,
# gcc/ud e intelc/mlx tienen 6 invocaciones (5 efectivas); intel/mlx tiene 12
# (6 en fase_b.sh + 6 en fase_b_intelc.sh, 10 efectivas). Esto vale para EP-8n,
# FT-8n y CG-8n. Fuente: matriz T14, tiempos intel/mlx a 8n y 11 rondas:
# ep_ft=4,985567 min, cg=2,961333 min (informes/tareas/T14/tiempos.txt).
# Fórmula T26: ep_ft 4,985567×4×6/11×1,3+10=24,1 -> 25 min; cg
# 2,961333×4×6/11×1,3+10=18,4 -> 20 min; intelc ep_ft con 2 pares=17,1 -> 20;
# intelc cg con 2 pares=14,2 -> 15. Reserva: sonda 9×0,5=4,5 nodo-h;
# medidas 2×8×(25+20+20+15)/60=21,33; total 25,83 nodo-h.
# Destino posterior del sync T27: data/raw/b9p07/<A|B>/.
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"; cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="37ee61482936c269a9753ab17055e84ae7cdd834"
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
[ "$ACTUAL" = "$EXPECTED_COMMIT" ] || echo "AVISO: .deploy-commit ($ACTUAL) != commit de referencia ($EXPECTED_COMMIT); rigen las puertas SHA"
check_sha() { local real; real="$(sha256sum "$1" | awk '{print $1}')"; [ "$real" = "$2" ] || { echo "!! sha256 NO coincide: $1 (esperado $2, real $real)" >&2; exit 4; }; echo "sha256 OK: $1"; }
check_sha experiments/fase_b.sh e847876a2051c326d07a12a2b66d2f2c8c857a6ff7649fd5e16d4489a85de8b5
check_sha experiments/fase_b_intelc.sh e23dd72335325bf59ada8f0acdec0fbd16fb28edfbf406738f1a0bbb89d80d37
check_sha experiments/helpers/sonda_red.sbatch 9bafecd178cb46a6c1b5c3f5e08ab9a61fa5307b50231e4a2041952ac165d5e7
mkdir -p data/raw/b9p07
A="b9p06,b9p07,b9p08,b9p09,b9p10,b9p11,b9p13,b9p16"
B="b9p06,b9p08,b9p09,b9p10,b9p11,b9p13,b9p14,b9p16"
sbatch --parsable --nodes=9 --nodelist=b9p06,b9p07,b9p08,b9p09,b9p10,b9p11,b9p13,b9p14,b9p16 --time=00:30:00 --job-name=L10-sonda experiments/helpers/sonda_red.sbatch
for conjunto in A B; do
  nodos="${A}"; [ "$conjunto" = B ] && nodos="${B}"
sbatch --parsable --nodes=8 --nodelist="$nodos" --time=00:25:00 --job-name="L10-${conjunto}-ft" experiments/fase_b.sh ep_ft 1 6
sbatch --parsable --nodes=8 --nodelist="$nodos" --time=00:20:00 --job-name="L10-${conjunto}-cg" experiments/fase_b.sh cg 1 6
sbatch --parsable --nodes=8 --nodelist="$nodos" --time=00:20:00 --job-name="L10-${conjunto}-ft-intelc" experiments/fase_b_intelc.sh ep_ft 1 6
sbatch --parsable --nodes=8 --nodelist="$nodos" --time=00:15:00 --job-name="L10-${conjunto}-cg-intelc" experiments/fase_b_intelc.sh cg 1 6
done
