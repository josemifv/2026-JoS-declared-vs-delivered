#!/usr/bin/env bash
# launch/20261006-L5-diag-ep-v3.sh — Diagnóstico EP v3 (D15)
#
# Objetivo:     Reproducir la anomalía EP/intel (0,53-0,60×) en las condiciones
#               EXACTAS de la matriz de fase B: binarios ep.D.x reales; gcc 64r con
#               ppr:32:package --bind-to core + UCX_TLS=rc,sm,self; intel 64r y 32r
#               con I_MPI_PIN_PROCESSOR_LIST=0-31,56-87; 2 repeticiones por caso;
#               por rank: cpu MHz (/sys cpufreq), hilos, afinidad real y utime.
# Autorización: DEVIATIONS 2026-10-06 D15 (amplía E74, 2026-10-05); NIVEL 2 (R7),
#               dirigido: no entra en fichas ni rankings.
# Scripts:      experiments/diag_ep_intel.sbatch (v3) — commit 76a7d8091ebb0518ce57dcb673534211f434fa95
# Estimación:   1 job de 1 nodo cpu112c × 00:20:00 (6 runs de EP D de ~2-3 s + sondas).
# Humo (QA a-h): 83800 (v2 del diagnóstico, 1 rep por caso) — sonda validada: exit
#               real por rank (sin la carrera de 83734), ranks registrados, ldd y env
#               capturados; sincronizado y verificado. La v3 cambia el BINDING (que es
#               el objeto del diagnóstico): la verificación del mapa real va dentro de
#               la propia sonda (afinidad por rank frente al mapa pedido de la matriz).
#               QA: a✓ (1 nodo, 64 r/n = forma de la celda EP-1n de la matriz) b✓
#               (afinidad real por rank = mapa de la matriz; ldd del ep.D.x por pila)
#               c (EP no lleva patrón de clase; el caso que debe fallar del patrón NPB
#               ya probado: ft.B.x → FALLO ✓) d✓ e✓ (trazado a D15/E74/R7) f✓ (salida
#               a la persona) g✓ (sync + verifica_raw) h (este fichero).
# Dependencias: propuesta: donde no compita con la serie de 8 nodos (1 nodo, cpu112c);
#               puede correr en paralelo con L1/L2 (nodo distinto de los 8 asignados).
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261006-L5-diag-ep-v3.sh
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"
cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="76a7d8091ebb0518ce57dcb673534211f434fa95"
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
[ "$ACTUAL" = "$EXPECTED_COMMIT" ] || { echo "!! .deploy-commit ($ACTUAL) != commit de los scripts ($EXPECTED_COMMIT)" >&2; exit 2; }
mkdir -p data/raw/diag

J="$(sbatch --parsable --nodelist=b9p03 --time=00:20:00 experiments/diag_ep_intel.sbatch)"
echo "L5 diagnóstico EP v3 lanzado: job=$J"
