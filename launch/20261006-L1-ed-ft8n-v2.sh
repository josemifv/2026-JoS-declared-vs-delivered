#!/usr/bin/env bash
# launch/20261006-L1-ed-ft8n-v2.sh — E-d: celda ingenua frente a recomendada (8 nodos)
#
# QUÉ CAMBIA RESPECTO A v1 (Prompt C 7): (1) verificación del sha256 desplegado de
# cada script ANTES de cualquier sbatch — aborta con exit 4 sin lanzar nada (regla 9,
# QA h); (2) parámetro DEPENDE_DE=<jobid> que añade -d afterany al PRIMER sbatch, para
# que la persona encadene el orden en cpu112c (L1 → L5 → L6 → L2a); (3) cabecera con
# los sha256 de los scripts y los nodos fijos.
# Objetivo:     FT clase D a 8 nodos × 64 r/n (512), modo ingenuo (gcc/Open MPI por
#               defecto, Slurm elige nodos) frente a recomendado (intel/mlx, grupo
#               SMT-off, mapa explícito), 11 rondas (1 calentamiento + 10 efectivas).
# Autorización: DEVIATIONS E-d 2026-10-02, ampliación 2026-10-04 y orden alternado
#               2026-10-05 (E67). QA a-h completa (humos 83735/83736).
# Scripts (sha256 en el commit de referencia; regla 9):
#   experiments/ed_ft.sbatch 615a6a44f1e822563b4ba6e9e5f4ccfb5e15381c82099a215bc6ee29493a867e
# Nodos fijos:   las 8 asignaciones piden 8 nodos cualesquiera (el ingenuo SIN
#               --exclude; el recomendado con --exclude=b9p02,b9p12). SIN nodos fijos
#               propios. NOTA (Prompt C 7.3): b9p03 es nodo fijo de L2, L5 y L7 y
#               PUEDE coincidir con alguna asignación de esta cadena — el --exclusive
#               impide el solape simultáneo; en serie comparten nodo entre asignaciones.
# Estimación:   8 jobs de 8 nodos × ≤ 00:40:00, cola compartida --exclusive.
# Humo (QA a-h): 83735 (ingenuo 1 ronda) y 83736 (recomendado 1 ronda) — COMPLETED;
#               exit real 0, SUCCESSFUL + clase D, map-check por modo, ldd correcto,
#               nodos/SMT registrados; sincronizados y verificados (verifica_raw 0
#               fallos). QA: a✓ b✓ c✓ d✓ e✓ f✓ g✓ h✓ (este fichero, con sha256 abajo).
# Dependencias: PRIMERA de la serie cpu112c si nadie la encadena; la persona fijará
#               el orden L1 → L5 → L6 → L2a con DEPENDE_DE al lanzar.
# sha256 de ESTE fichero: anotado en informes/estado-lineas.md para su aprobación.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261006-L1-ed-ft8n-v2.sh
#            (encadenada: DEPENDE_DE=<jobid_previo> ssh turgalium 'bash -s' < ...)
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"
cd "$REPO"                                   # cd explícito a la raíz del checkout (regla 10)
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="701ec01fb042a7c9361fd884af423ae101fe421f"   # commit con los scripts
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
if [ "$ACTUAL" != "$EXPECTED_COMMIT" ]; then
  echo "AVISO: .deploy-commit ($ACTUAL) != commit de referencia ($EXPECTED_COMMIT); rige el sha256 individual"
fi
# regla 9 / QA h: puerta DURA por sha256 — aborta (exit 4) sin lanzar nada
check_sha() { # $1 = ruta; $2 = sha256 esperado
  local real
  real="$(sha256sum "$1" | awk '{print $1}')"
  if [ "$real" != "$2" ]; then
    echo "!! sha256 desplegado de $1 NO coincide (esperado $2, real $real)" >&2
    exit 4
  fi
  echo "sha256 OK: $1"
}
check_sha experiments/ed_ft.sbatch 615a6a44f1e822563b4ba6e9e5f4ccfb5e15381c82099a215bc6ee29493a867e
mkdir -p data/raw/infrautil

DEP="${DEPENDE_DE:-}"
DEPOPT=""
[ -n "$DEP" ] && DEPOPT="-d afterany:$DEP"

# Orden alternado (DEVIATIONS 2026-10-05): I1→R1→I2→R2→I3→R3→I4→R4, cadena afterany.
I1="$(sbatch --parsable $DEPOPT --nodes=8 --time=00:40:00 experiments/ed_ft.sbatch ingenuo 1 3)"
R1="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=00:40:00 -d afterany:$I1 experiments/ed_ft.sbatch recomendado 1 3)"
I2="$(sbatch --parsable --nodes=8 --time=00:40:00 -d afterany:$R1 experiments/ed_ft.sbatch ingenuo 4 6)"
R2="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=00:40:00 -d afterany:$I2 experiments/ed_ft.sbatch recomendado 4 6)"
I3="$(sbatch --parsable --nodes=8 --time=00:40:00 -d afterany:$R2 experiments/ed_ft.sbatch ingenuo 7 9)"
R3="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=00:40:00 -d afterany:$I3 experiments/ed_ft.sbatch recomendado 7 9)"
I4="$(sbatch --parsable --nodes=8 --time=00:40:00 -d afterany:$R3 experiments/ed_ft.sbatch ingenuo 10 11)"
R4="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=00:40:00 -d afterany:$I4 experiments/ed_ft.sbatch recomendado 10 11)"
echo "L1-v2 E-d lanzado: I1=$I1 R1=$R1 I2=$I2 R2=$R2 I3=$I3 R3=$R3 I4=$I4 R4=$R4 (final=$R4)"
