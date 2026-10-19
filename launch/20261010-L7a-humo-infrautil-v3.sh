#!/usr/bin/env bash
# launch/20261010-L7a-humo-infrautil-v3.sh — HUMO de infrautilización (D19: FT clase D)
#
# QUÉ CAMBIA RESPECTO A v2 (T07): T02/T03/T04: entorno por celda y map-check corregidos; STREAM solo gcc
# con stream_<arch>_200M, sin sobrescribir fase B. Puerta del validador v2 (T28).
# Se conservan los cuatro humos de una ronda y sus dependencias de compilación.
# Pendiente de aprobación humana por SHA; T07 no despliega ni lanza.
#
# HISTORIAL v2 — QUÉ CAMBIA RESPECTO A v1 (Prompt C 7): (1) verificación del sha256 desplegado de
# cada script antes de cualquier sbatch — aborta exit 4 (regla 9, QA h); (2) SIN
# compile_ft_spr (D19: FT clase D, los ft.D.x de fase B ya verificados — Prompt C 3.8);
# (3) CON la recompilación de STREAM a STREAM_ARRAY_SIZE=200000000 (Prompt C 3.7,
# helpers/compile_stream_big.sbatch: spr+clx, solo gcc (D20/T04), -mcmodel=medium; verifica
# que la salida imprime "Array size = 200000000"); (4) infrautil.sh corregido por T02/T03/T04/T28 (D19 + rank_wrap
# arreglado + map-check validado con FALLO-MAPA + mapas b9p-on correctos + STREAM por
# defecto con unset + OMP_DISPLAY_AFFINITY); (5) DEPENDE_DE; (6) --time=02:30:00: con
# clase D una ronda dura ~40-60 min por nodo según los humos 83839-83842 y 83871-83873
# (FT D por defecto: 250-255 s a 16r, 156-158 s a 32r en cpu112c — D19).
# Objetivo:     QA a-h de la infrautilización: 1 RONDA en los 4 nodo-grupo (b9p-off,
#               b9p-on, c36-off, c36-on): STREAM (arrays 200M), FT clase D y EP ×
#               16/32(/56/64 en b9p; FT-56 saltado por potencia de 2) × binding
#               default/explícito; STREAM solo gcc (D20), FT/EP gcc e intel.
# Autorización: DEVIATIONS 2026-10-06 D19 (revierte D3) y D17 (estructura 10+1 en 4
#               jobs); humos de 1 ronda del bloque C; P-E77 (la validación del
#               map-check es LO QUE ESTE HUMO DEBE PROBAR: sin map-check gcc explicit
#               correcto previo).
# Scripts (sha256 en el commit de referencia; regla 9):
#   experiments/infrautil.sh 384f0b8e7ad7fd830699fe2dfa05bb9e870853a5ab28c4a06ed04164e07cd68c
#   experiments/lib/valida_job.sh 5b0be94bf254af857481c753d4766129429cab7195af77ebf4333c14c65ed27f
#   experiments/helpers/compile_stream_big.sbatch ec6e064d4426f5d2ca9f47942c92f1f4c693fcd49c68a2569cc57f9d96460afb
# Nodos fijos:   b9p-off usa b9p03 — NOTA (Prompt C 7.3): b9p03 es nodo fijo de L2,
#               L5 y L7 y PUEDE coincidir con las cadenas de 8 nodos (--exclusive
#               evita solape); b9p-on = b9p02; c36-off = aac102; c36-on = acc101
#               (representantes con --nodelist; SMT validado en el arranque).
# Estimación:   5 jobs: 1 de compilación STREAM (cpu112c, 00:20:00) + 4 humos de
#               1 nodo × 02:30:00.
# Humo:         ESTE fichero ES el humo de la infrautilización corregida. ATENCIÓN:
#               los datos de humo gcc explicit de 83871-83873 NO son utilizables
#               (P-E77: mapchecks con cpus=0 y manifiestos sin validación de mapa).
#               QA a completar con su ejecución: a (1 nodo, 16/32/64 r) b (map-check
#               POR CELDA VALIDADO: gcc rank i = cpu i-ésima; intel conjunto igual y
#               1 cpu/rank; STREAM hilo i = cpu i-ésima — FALLO-MAPA si no) c (Size
#               clase D contra salida real; caso que debe fallar: ft.B.x → FALLO ✓)
#               d (exit real) e (trazado a D19/D17/P-E77/E16-SMT/R10) f (salida a la
#               persona antes de L7b-v3) g (sync + verifica_raw) h (este fichero).
# Dependencias: los 2 jobs cpu112c después de la serie de 8 nodos o donde no compitan
#               (encadenable con DEPENDE_DE); los 2 de cpu36c EN PARALELO con L3.
#               L7b-v3 requiere este humo sincronizado y revisado.
# sha256 de ESTE fichero: anotado en informes/estado-lineas.md.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261010-L7a-humo-infrautil-v3.sh
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
check_sha experiments/infrautil.sh 384f0b8e7ad7fd830699fe2dfa05bb9e870853a5ab28c4a06ed04164e07cd68c
check_sha experiments/lib/valida_job.sh 5b0be94bf254af857481c753d4766129429cab7195af77ebf4333c14c65ed27f
check_sha experiments/helpers/compile_stream_big.sbatch ec6e064d4426f5d2ca9f47942c92f1f4c693fcd49c68a2569cc57f9d96460afb
mkdir -p data/raw/infrautil

DEP="${DEPENDE_DE:-}"
DEPOPT=""
[ -n "$DEP" ] && DEPOPT="-d afterany:$DEP"

# 0) recompilar STREAM con STREAM_ARRAY_SIZE=200000000 (Prompt C 3.7): spr+clx,
#    solo gcc, stream_spr_200M y stream_clx_200M; no modifica los binarios
#    de fase B y verifica "Array size = 200000000" en su salida (T04/D20)
K="$(sbatch --parsable $DEPOPT -p cpu112c --time=00:20:00 experiments/helpers/compile_stream_big.sbatch)"
# 1) humos de 1 ronda, un job por nodo-grupo; los dos cpu112c tras la compilación
#    (necesitan el binario nuevo); los dos cpu36c en paralelo (necesitan el clx del
#    mismo job de compilación → afterok:$K igualmente)
H1="$(sbatch --parsable -p cpu112c --nodelist=b9p03 --time=02:30:00 -d afterok:$K \
      experiments/infrautil.sh b9p-off 1)"
H2="$(sbatch --parsable -p cpu112c --nodelist=b9p02 --time=02:30:00 -d afterok:$K \
      experiments/infrautil.sh b9p-on 1)"
H3="$(sbatch --parsable -p cpu36c --nodelist=aac102 --time=02:30:00 -d afterok:$K \
      experiments/infrautil.sh c36-off 1)"
H4="$(sbatch --parsable -p cpu36c --nodelist=acc101 --time=02:30:00 -d afterok:$K \
      experiments/infrautil.sh c36-on 1)"
echo "L7a-v3 humo infrautil lanzado: compile-stream-big=$K humos=$H1,$H2,$H3,$H4"
