#!/usr/bin/env bash
# QUÉ CAMBIA RESPECTO A v3 (T41): se excluye b9p07 por orden informes/ordenes/2026-10-11-T41-L2-v4.md; jobs 83707 y 83708 registran 39% menos ancho de banda.
# QUÉ CAMBIA RESPECTO A v2 (T17): sha256 actuales tras T05 y T28;
# validador v2 incluido en las puertas SHA. No se despliega ni lanza en T17.
# FT-8n incluye intelc/mlx (D21): 5 runs de humo a 8x64 ranks,
# más dos controles D-B. La medida usa los transportes Intel de la
# R2 del propio ligero; OSU no se repite para intelc.
# launch/20261011-L2a-humo-ligero112-v4.sh — HUMO del protocolo ligero INDEPENDIENTE
# de cpu112c (D18): verificación funcional + 1 ronda de colectivas + 1 ronda de FT-8n.
#
# QUÉ CAMBIA RESPECTO A v1 (Prompt C 7): (1) verificación del sha256 desplegado de
# cada script antes de cualquier sbatch — aborta exit 4 (regla 9, QA h); (2) parámetro
# DEPENDE_DE para el encadenado por la persona (L1 → L5 → L6 → L2a); (3) los scripts
# llevan las correcciones del Prompt C (CMDLOG_DIR ligero112, pin coll intel en
# env_par, alltoall gcc/tcp SALTADA-declarada, control pt2pt 128, tcp como fase A).
# Objetivo:     QA a-h del ligero112 antes de L2b/L2c: verificación de los 7 combos
#               (probe exit 0 + transporte observado = pedido + map-check 64 r/n +
#               ldd), humo de colectivas (1 ronda, 512 ranks) y humo de FT-8n
#               (1 ronda, 5 pares: candidatos de la matriz más intelc/mlx).
# Autorización: DEVIATIONS 2026-10-06 D18; QA permanente a-g de AGENTS.md.
# Scripts (sha256 en el commit de referencia; regla 9):
#   experiments/ligero112_verif.sbatch c72705ae107f3c912d1c295b351e27e13f963cf9a76c02a16ece5f00f9ed72ce
#   experiments/ligero112_osu.sbatch   89e395bd9520026b63780dda6452244c6064cce596dd531b233ca7529b7391e8
#   experiments/ligero112_ft8n.sbatch  ffb5a795a4af2a77f1a6d23d486b69516ab2232883f6c22c682c8fab6d2a66e7
#   experiments/helpers/ligero36_pin.sh 6788d173ae493d8293b87c76fdc156522953407ad9ff5d48eb5601987bde280b
#   experiments/lib/valida_job.sh 5b0be94bf254af857481c753d4766129429cab7195af77ebf4333c14c65ed27f
# Nodos fijos:   verif y pt2pt futuro: par intra-switch b9p03,b9p04; coll/ft8n: 8
#               cualesquiera SMT-off (--exclude=b9p02,b9p12,b9p07). NOTA (Prompt C 7.3):
#               b9p03 es nodo fijo de L2, L5 y L7 y PUEDE coincidir con las cadenas
#               de 8 nodos — el --exclusive impide el solape simultáneo.
# Estimación:   3 jobs: verif 2 nodos 00:30:00; coll humo 8 nodos 01:00:00; ft8n
#               humo 8 nodos 01:00:00.
# Humo:         ESTE fichero ES el humo (L2a); QA a completar con su ejecución
#               (b: map-check 64 r/n + ldd + transporte observado; c: patrones contra
#               salida real — caso que debe fallar ya probado: ft.B.x → FALLO;
#               d: exit real en manifiesto; e: trazado a D18/E-f/R1/P-2/P-5; f: salida
#               a la persona antes de L2b; g: sync a data/raw/ligero112/ + verifica_raw
#               tras cada job; h: este fichero y su sha256).
# Dependencias: la persona encadena el orden cpu112c (L1 → L5 → L6 → L2a) con
#               DEPENDE_DE. L2b requiere este humo sincronizado y revisado.
# sha256 de ESTE fichero: anotado en informes/estado-lineas.md.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261011-L2a-humo-ligero112-v4.sh
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"
cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="2a03b78d0df864d6846167849f89e0b14c91f739"
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
check_sha experiments/ligero112_verif.sbatch c72705ae107f3c912d1c295b351e27e13f963cf9a76c02a16ece5f00f9ed72ce
check_sha experiments/ligero112_osu.sbatch 89e395bd9520026b63780dda6452244c6064cce596dd531b233ca7529b7391e8
check_sha experiments/ligero112_ft8n.sbatch ffb5a795a4af2a77f1a6d23d486b69516ab2232883f6c22c682c8fab6d2a66e7
check_sha experiments/helpers/ligero36_pin.sh 6788d173ae493d8293b87c76fdc156522953407ad9ff5d48eb5601987bde280b
check_sha experiments/lib/valida_job.sh 5b0be94bf254af857481c753d4766129429cab7195af77ebf4333c14c65ed27f
mkdir -p data/raw/ligero112

DEP="${DEPENDE_DE:-}"
DEPOPT=""
[ -n "$DEP" ] && DEPOPT="-d afterany:$DEP"

V="$(sbatch --parsable $DEPOPT --nodelist=b9p03,b9p04 --time=00:30:00 experiments/ligero112_verif.sbatch)"
C="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12,b9p07 --time=01:00:00 -d afterok:$V \
      experiments/ligero112_osu.sbatch coll 1 1)"
F="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12,b9p07 --time=01:00:00 -d afterany:$C \
      experiments/ligero112_ft8n.sbatch 1 1 "gcc rc" "intel mlx" "gcc dc" "intel verbs;ofi_rxm" "intelc mlx")"
echo "L2a-v4 humo ligero112 lanzado: verif=$V coll=$C ft8n=$F (final=$F)"
