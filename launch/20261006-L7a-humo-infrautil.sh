#!/usr/bin/env bash
# launch/20261006-L7a-humo-infrautil.sh — HUMO de infrautilización con FT clase C (D3)
#
# Objetivo:     QA a-h de la infrautilización con la clase de FT decidida (D3:
#               clase C en todos los tamaños): recompilar ft.C.x de spr (los
#               existentes son del 30-09, era -march=native, clase dudosa —
#               verificado 2026-10-06 con mtimes y hashes: los 8 ft.*.x son
#               distintos entre sí, pero los spr no tienen el make.def de fase B)
#               y lanzar 1 RONDA en los 4 nodo-grupo (b9p-off, b9p-on, c36-off,
#               c36-on): STREAM, FT C y EP × 16/32(/56/64 en b9p; FT-56 saltado
#               por potencia de 2) × binding default/explícito.
# Autorización: DEVIATIONS 2026-10-06 D3 (cierra E76) y D17 (estructura 10+1 en 4
#               jobs); humos de 1 ronda del bloque C.
# Scripts:      experiments/infrautil.sh (v8), helpers/compile_ft_spr.sbatch —
#               commit 76a7d8091ebb0518ce57dcb673534211f434fa95
# Estimación:   5 jobs: 1 de compilación (cpu112c, 00:20:00) + 4 humos de 1 nodo
#               × 01:30:00 (FT C a 16 ranks ≈ 8 min × 2 bindings + EP + STREAM +
#               map-checks).
# Humo (QA a-h): ESTE fichero ES el humo de FT-C (sin humo previo de esta clase);
#               el RESTO de celdas (STREAM, EP, map-checks, taskset por rank) quedó
#               validado por los humos v4/v7b (83731-83738, 83839-83842, 83871-83873)
#               y la cancelación de 83871-83873 (FT D inviable) está registrada (E76).
#               QA a completar con su ejecución: a (misma forma/tamaño: 1 nodo,
#               16/32/64 r) b (map-check POR CELDA con taskset por rank; SMT del
#               nodo validado en el arranque) c (Size clase C = 512x512x512 contra
#               salida real; caso que debe fallar: ft.B.x vs patrón C → FALLO,
#               probado contra salida real en calib36-83379) d (exit real) e
#               (trazado a D3/D17/E76/E16-SMT/R10) f (salida a la persona antes de
#               L7b) g (sync + verifica_raw) h (este fichero y su sha256).
# Dependencias: los 2 jobs cpu112c después de la serie de 8 nodos o donde no
#               compitan (1 nodo cada uno); los 2 de cpu36c EN PARALELO con L3
#               (partición cpu36c, nodos representantes disjuntos de los 8 de L3:
#               aac102/acc101 no están en aac/acc112-119). L7b requiere este humo
#               revisado + aprobación de la persona.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261006-L7a-humo-infrautil.sh
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"
cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="76a7d8091ebb0518ce57dcb673534211f434fa95"
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
[ "$ACTUAL" = "$EXPECTED_COMMIT" ] || { echo "!! .deploy-commit ($ACTUAL) != commit de los scripts ($EXPECTED_COMMIT)" >&2; exit 2; }
mkdir -p data/raw/infrautil

# 0) recompilar ft.C.x spr (gcc+intel) con el make.def de fase B; árbol limpio;
#    el binario dudoso del 30-09 se conserva como .pre-v8
K="$(sbatch --parsable -p cpu112c --time=00:20:00 experiments/helpers/compile_ft_spr.sbatch)"
# 1) humos de 1 ronda, un job por nodo-grupo (representantes con --nodelist;
#    SMT validado en el arranque del script). Los dos cpu112c en paralelo [O]
#    (D17), tras la compilación; los dos cpu36c no dependen del compile (clx
#    verificado) y salen en paralelo con L3.
H1="$(sbatch --parsable -p cpu112c --nodelist=b9p03 --time=01:30:00 -d afterok:$K \
      experiments/infrautil.sh b9p-off 1)"
H2="$(sbatch --parsable -p cpu112c --nodelist=b9p02 --time=01:30:00 -d afterok:$K \
      experiments/infrautil.sh b9p-on 1)"
H3="$(sbatch --parsable -p cpu36c --nodelist=aac102 --time=01:30:00 \
      experiments/infrautil.sh c36-off 1)"
H4="$(sbatch --parsable -p cpu36c --nodelist=acc101 --time=01:30:00 \
      experiments/infrautil.sh c36-on 1)"
echo "L7a humo infrautil FT-C lanzado: compile=$K humos=$H1,$H2,$H3,$H4"
