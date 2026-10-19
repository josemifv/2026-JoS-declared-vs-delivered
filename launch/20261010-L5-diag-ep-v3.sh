#!/usr/bin/env bash
# launch/20261010-L5-diag-ep-v3.sh — Diagnóstico EP v3.1 (D15)
#
# QUÉ CAMBIA RESPECTO A v2 (T07): SHA actual tras T01; mismo diagnóstico EP, sin cambiar jobs ni parámetros.
# Pendiente de aprobación humana por SHA; T07 no despliega ni lanza.
#
# HISTORIAL v2 — QUÉ CAMBIA RESPECTO A v1 (Prompt C 7): (1) verificación del sha256 desplegado del
# script antes del sbatch — aborta exit 4 (regla 9, QA h); (2) DEPENDE_DE para el
# encadenado por la persona (L1 → L5 → L6 → L2a); (3) cabecera con nodos fijos.
# Objetivo:     Reproducir la anomalía EP/intel (0,53-0,60×) en las condiciones
#               EXACTAS de la matriz de fase B: binarios ep.D.x reales; gcc 64r con
#               ppr:32:package --bind-to core + UCX_TLS=rc,sm,self; intel 64r y 32r
#               con I_MPI_PIN_PROCESSOR_LIST=0-31,56-87; 2 repeticiones por caso;
#               por rank: cpu MHz muestreada cada 5 s (fichero por rank), hilos,
#               afinidad real y utime de hijos (times en el shell del wait).
# Autorización: DEVIATIONS 2026-10-06 D15 (amplía E74, 2026-10-05); NIVEL 2 (R7),
#               dirigido: no entra en fichas ni rankings.
# Scripts (sha256 en el commit de referencia; regla 9):
#   experiments/diag_ep_intel.sbatch 14d9ea58fcf28fb98cae1aba41cbe4a2c46c8e02434d3318b9f10a0233b51a69
# Nodos fijos:   b9p03 (--nodelist). NOTA (Prompt C 7.3): b9p03 es nodo fijo de L2,
#               L5 y L7 y PUEDE coincidir con las cadenas de 8 nodos — el --exclusive
#               impide el solape simultáneo.
# Estimación:   1 job de 1 nodo cpu112c × 00:20:00 (6 runs de EP D de ~2-3 s + sondas).
# Humo (QA a-h): 83800 (v2 del diagnóstico, 1 rep por caso) — sonda validada: exit
#               real por rank (sin la carrera de 83734), ranks registrados, ldd y env
#               capturados; sincronizado y verificado. La v3 cambia el BINDING (que es
#               el objeto del diagnóstico): la verificación del mapa va dentro de la
#               propia sonda (afinidad por rank frente al mapa pedido de la matriz).
#               QA: a✓ (1 nodo, 64 r/n = forma de la celda EP-1n de la matriz) b✓
#               c (el caso que debe fallar del patrón NPB ya probado: ft.B.x → FALLO)
#               d✓ e✓ (trazado a D15/E74/R7) f✓ g✓ (sync + verifica_raw) h✓ (este
#               fichero).
# Dependencias: la persona encadena (L1 → L5 → L6 → L2a) con DEPENDE_DE.
# sha256 de ESTE fichero: anotado en informes/estado-lineas.md.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261010-L5-diag-ep-v3.sh
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"
cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="d418104bc45dd2695b72d5a46561a4b267aaea37"
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
check_sha experiments/diag_ep_intel.sbatch 14d9ea58fcf28fb98cae1aba41cbe4a2c46c8e02434d3318b9f10a0233b51a69
mkdir -p data/raw/diag

DEP="${DEPENDE_DE:-}"
DEPOPT=""
[ -n "$DEP" ] && DEPOPT="-d afterany:$DEP"

J="$(sbatch --parsable $DEPOPT --nodelist=b9p03 --time=00:20:00 experiments/diag_ep_intel.sbatch)"
echo "L5-v3 diagnóstico EP v3.1 lanzado: job=$J"
