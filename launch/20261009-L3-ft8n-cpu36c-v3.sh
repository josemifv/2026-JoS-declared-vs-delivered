#!/usr/bin/env bash
# launch/20261009-L3-ft8n-cpu36c-v3.sh — FT-8n cpu36c con intelc
#
# Objetivo: humo previo (una ronda, SMT-off, 5 pares) y, solo con argumento
# «medida», medida completa en SMT-off y SMT-on: 2 × 11 × 5 = 110 runs,
# más controles D-B por job. El humo 83726 cubría los cuatro pares anteriores;
# no cubría intelc.
# Autorización: T18; depende de T13 verificada; D16/D21/E-f y R2 de cpu36c.
# No lanzar la medida sin revisar primero el humo y obtener aprobación.
# Pares: "gcc rc" "intel mlx" "gcc dc" "intel verbs;ofi_rxm" "intelc mlx".
# Script: experiments/ligero36_ft8n.sbatch (v3, intelc clx/ft.D.x, pin 0-15,18-33).
# Estimación: humo 1 job de 8 nodos × 01:00:00; medida 2 jobs de 8 nodos × 01:00:00,
# grupos disjuntos y 110 runs más controles.
# Uso: ssh turgalium 'bash -s' < launch/20261009-L3-ft8n-cpu36c-v3.sh
#       ssh turgalium 'bash -s' < launch/20261009-L3-ft8n-cpu36c-v3.sh medida
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"
cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="df808aa4d8f1041e1da67a18435d5f3f3db094fa"
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
if [ "$ACTUAL" != "$EXPECTED_COMMIT" ]; then
  echo "AVISO: .deploy-commit ($ACTUAL) != commit de referencia ($EXPECTED_COMMIT); rige el sha256 individual"
fi
check_sha() {
  local real
  real="$(sha256sum "$1" | awk '{print $1}')"
  [ "$real" = "$2" ] || { echo "!! sha256 NO coincide: $1 (esperado $2, real $real)" >&2; exit 4; }
  echo "sha256 OK: $1"
}
# La puerta fija el script desplegado que fue revisado para esta versión.
SCRIPT_SHA="$(sha256sum launch/20261009-L3-ft8n-cpu36c-v3.sh | awk '{print $1}')"
check_sha experiments/ligero36_ft8n.sbatch 5c10cc7e43ec617aae4039d9beeb319db82fecea6e691de6315dbeed6333c820
mkdir -p data/raw/ligero
PAIRS=("gcc rc" "intel mlx" "gcc dc" "intel verbs;ofi_rxm" "intelc mlx")
MODE="${1:-humo}"
case "$MODE" in
  humo)
    F1="$(sbatch --parsable --nodes=8 --nodelist=aac112,aac113,aac114,aac115,aac116,aac117,aac118,aac119 \
      --time=01:00:00 experiments/ligero36_ft8n.sbatch 1 1 "${PAIRS[@]}")"
    echo "L3-v3 humo FT-8n cpu36c lanzado: F1=$F1 sha256=$SCRIPT_SHA"
    ;;
  medida)
    F1="$(sbatch --parsable --nodes=8 --nodelist=aac112,aac113,aac114,aac115,aac116,aac117,aac118,aac119 \
      --time=01:00:00 experiments/ligero36_ft8n.sbatch 1 11 "${PAIRS[@]}")"
    F2="$(sbatch --parsable --nodes=8 --nodelist=acc112,acc113,acc114,acc115,acc116,acc117,acc118,acc119 \
      --time=01:00:00 experiments/ligero36_ft8n.sbatch 1 11 "${PAIRS[@]}")"
    echo "L3-v3 medida FT-8n cpu36c lanzada: F1=$F1 F2=$F2 sha256=$SCRIPT_SHA"
    ;;
  *) echo "uso: $0 [medida]" >&2; exit 2 ;;
esac
