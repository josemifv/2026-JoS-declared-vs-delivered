#!/usr/bin/env bash
# launch/20261006-L7b-infrautil.sh — Medida de infrautilización 10+1 (D17)
#
# Objetivo:     STREAM, FT clase C (D3) y EP × 16/32(/56/64 en b9p; FT-56 saltado
#               por potencia de 2) × binding default/explícito, 11 repeticiones
#               (1 calentamiento + 10 efectivas), en los 4 nodo-grupo (b9p-off,
#               b9p-on, c36-off, c36-on): UN job por nodo-grupo con todos los
#               bucles dentro (D17).
# Autorización: DEVIATIONS 2026-10-06 D17 (registra el envío del 2026-10-05) y D3;
#               prueba de infrautilización de AGENTS.md; E16 (SMT: b9p02/b9p12 y
#               cpu36c con nodo SMT-on).
# Scripts:      experiments/infrautil.sh (v8) — commit 76a7d8091ebb0518ce57dcb673534211f434fa95
# Estimación:   4 jobs de 1 nodo: cpu112c 03:30:00 c/u (FT C ≈ (8+4+2) min × 11 ×
#               2 bindings + STREAM/EP); cpu36c 03:30:00 c/u. Los DOS de cpu112c
#               EN PARALELO (D17) y los dos de cpu36c EN PARALELO.
# Humo (QA a-h): L7a (1 ronda en los 4 nodo-grupo, con ft.C.x spr recompilado) —
#               REQUERIDO, sincronizado y REVISADO por la persona antes de este
#               fichero. QA del humo aplicable a la medida: a-e y h; f se repite
#               al presentar L7b; g (sync + verifica_raw) tras cada job de la medida.
# Dependencias: REQUIERE el humo L7a COMPLETADO, sincronizado y REVISADO. Corre en
#               cpu112c donde no compita con la serie de 8 nodos (1 nodo por job) y
#               en cpu36c en paralelo con L3 si este sigue en cola.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261006-L7b-infrautil.sh
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"
cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="76a7d8091ebb0518ce57dcb673534211f434fa95"
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
[ "$ACTUAL" = "$EXPECTED_COMMIT" ] || { echo "!! .deploy-commit ($ACTUAL) != commit de los scripts ($EXPECTED_COMMIT)" >&2; exit 2; }
mkdir -p data/raw/infrautil

# Medida: 11 repeticiones (1 calentamiento + 10 efectivas), un job por nodo-grupo;
# los dos cpu112c en paralelo [O] (D17) y los dos cpu36c en paralelo.
M1="$(sbatch --parsable -p cpu112c --nodelist=b9p03 --time=03:30:00 \
      experiments/infrautil.sh b9p-off 11)"
M2="$(sbatch --parsable -p cpu112c --nodelist=b9p02 --time=03:30:00 \
      experiments/infrautil.sh b9p-on 11)"
M3="$(sbatch --parsable -p cpu36c --nodelist=aac102 --time=03:30:00 \
      experiments/infrautil.sh c36-off 11)"
M4="$(sbatch --parsable -p cpu36c --nodelist=acc101 --time=03:30:00 \
      experiments/infrautil.sh c36-on 11)"
echo "L7b infrautilización lanzado: M1=$M1 M2=$M2 M3=$M3 M4=$M4"
