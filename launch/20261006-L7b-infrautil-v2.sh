#!/usr/bin/env bash
# launch/20261006-L7b-infrautil-v2.sh — Medida de infrautilización 10+1 (D17, D19)
#
# QUÉ CAMBIA RESPECTO A v1 (Prompt C 7): (1) verificación del sha256 desplegado de
# cada script antes de cualquier sbatch — aborta exit 4 (regla 9, QA h); (2) DEPENDE_DE;
# (3) --time=PENDIENTE-HUMO: la v2 ABORTA si no se ha sustituido; se sustituirá en una
# v3 tras el humo L7a-v2 (Prompt C 7.6): --time = duración de la ronda del humo × 11 ×
# 1,3, redondeado arriba. MaxTime consultado el 2026-10-06 con `scontrol show
# partition`: cpu112c MaxTime=UNLIMITED y cpu36c MaxTime=UNLIMITED — sin tope del
# gestor; el límite de referencia es la nota de la persona: si la estimación supera
# las 10 h, se anota para la persona SIN buscar alternativas (la opción posible sería
# repartir gcc e intel en dos nodos del mismo grupo, decisión suya).
# Objetivo:     STREAM (arrays 200M), FT clase D (D19) y EP × 16/32(/56/64 en b9p;
#               FT-56 saltado por potencia de 2) × binding default/explícito, 11
#               repeticiones (1 calentamiento + 10 efectivas), en los 4 nodo-grupo
#               (b9p-off, b9p-on, c36-off, c36-on): UN job por nodo-grupo (D17).
# Autorización: DEVIATIONS 2026-10-06 D17 y D19; prueba de infrautilización de
#               AGENTS.md; E16 (SMT).
# Scripts (sha256 en el commit de referencia; regla 9):
#   experiments/infrautil.sh b4dedac00c6fac3c7d8ff178f25fc507bf32059484a2a2e93465dc63943aced5
# Nodos fijos:   b9p-off = b9p03; b9p-on = b9p02; c36-off = aac102; c36-on = acc101.
#               NOTA (Prompt C 7.3): b9p03 es nodo fijo de L2, L5 y L7 y PUEDE
#               coincidir con las cadenas de 8 nodos (--exclusive evita solape).
# Estimación:   4 jobs de 1 nodo; --time = PENDIENTE-HUMO (ver arriba); los DOS de
#               cpu112c EN PARALELO (D17) y los dos de cpu36c EN PARALELO.
# Humo (QA a-h): L7a-v2 — REQUERIDO, sincronizado y REVISADO por la persona antes de
#               este fichero. QA del humo aplicable a la medida: a-e y h; f se repite
#               al presentar L7b-v2; g (sync + verifica_raw) tras cada job.
# Dependencias: REQUIERE el humo L7a-v2 COMPLETADO, sincronizado y REVISADO, y la
#               sustitución del --time en una v3. Corre en cpu112c donde no compita
#               con la serie de 8 nodos y en cpu36c en paralelo con L3.
# sha256 de ESTE fichero: anotado en informes/estado-lineas.md.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261006-L7b-infrautil-v2.sh
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
check_sha experiments/infrautil.sh b4dedac00c6fac3c7d8ff178f25fc507bf32059484a2a2e93465dc63943aced5
mkdir -p data/raw/infrautil

# v2 (Prompt C 7.6): --time pendiente del humo L7a-v2; el fichero ABORTA sin lanzar
# mientras no se sustituya (se sustituirá en una v3 tras el humo).
T7B="PENDIENTE-HUMO"
if [ "$T7B" = "PENDIENTE-HUMO" ]; then
  echo "!! L7b-v2: --time=PENDIENTE-HUMO — sustituir en una v3 por la duración de la" >&2
  echo "   ronda del humo L7a-v2 × 11 × 1,3 (redondeado arriba); MaxTime cpu112c y" >&2
  echo "   cpu36c = UNLIMITED (scontrol show partition, 2026-10-06); límite de" >&2
  echo "   referencia de la persona: 10 h." >&2
  exit 5
fi

DEP="${DEPENDE_DE:-}"
DEPOPT=""
[ -n "$DEP" ] && DEPOPT="-d afterany:$DEP"

# Medida: 11 repeticiones, un job por nodo-grupo; los dos cpu112c EN PARALELO (D17).
M1="$(sbatch --parsable $DEPOPT -p cpu112c --nodelist=b9p03 --time=$T7B \
      experiments/infrautil.sh b9p-off 11)"
M2="$(sbatch --parsable -p cpu112c --nodelist=b9p02 --time=$T7B \
      experiments/infrautil.sh b9p-on 11)"
M3="$(sbatch --parsable -p cpu36c --nodelist=aac102 --time=$T7B \
      experiments/infrautil.sh c36-off 11)"
M4="$(sbatch --parsable -p cpu36c --nodelist=acc101 --time=$T7B \
      experiments/infrautil.sh c36-on 11)"
echo "L7b-v2 infrautilización lanzado: M1=$M1 M2=$M2 M3=$M3 M4=$M4"
