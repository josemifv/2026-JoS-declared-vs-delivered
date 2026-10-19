#!/usr/bin/env bash
# launch/20261006-L2b-osu112-completo-v2.sh — OSU COMPLETO del protocolo ligero
# INDEPENDIENTE de cpu112c (D18): pt2pt + colectivas de los 7 pares.
#
# QUÉ CAMBIA RESPECTO A v1 (Prompt C 7): (1) verificación del sha256 desplegado de
# cada script antes de cualquier sbatch — aborta exit 4 (regla 9, QA h); (2)
# DEPENDE_DE; (3) los scripts llevan las correcciones del Prompt C (pin coll intel
# en env_par: map-check y run con el MISMO entorno; alltoall gcc/tcp SALTADA-
# declarada; control pt2pt de 128 procs; tcp como fase_a.sh:86-96/125-127;
# CMDLOG_DIR ligero112).
# Objetivo:     Datos OSU propios del ligero para la R2 del D18: pt2pt (latency/bw,
#               8 B–4 MiB, UN par intra-switch: b9p03↔b9p04) y colectivas
#               (allreduce/alltoall ≤ 256 KiB, 8 nodos SMT-off × 64 r/n),
#               11 rondas intercaladas (1 calentamiento + 10 efectivas), control
#               D-B al inicio y fin de cada asignación.
# Autorización: DEVIATIONS 2026-10-06 D18; rangos de 2026-10-03 (fase A); P-2/P-5.
# Scripts (sha256 en el commit de referencia; regla 9):
#   experiments/ligero112_osu.sbatch 4fd0c754f578322b8f70607babbdd625ff18cee4578c8cd7d4a7efea8ee40079
#   experiments/helpers/ligero36_pin.sh 6788d173ae493d8293b87c76fdc156522953407ad9ff5d48eb5601987bde280b
# Nodos fijos:   pt2pt: b9p03,b9p04 (intra-switch); colectivas: 8 cualesquiera
#               SMT-off (--exclude=b9p02,b9p12). b9p03 es nodo fijo de L2, L5 y L7
#               y puede coincidir con las cadenas de 8 nodos (--exclusive evita solape).
# Estimación:   5 jobs: pt2pt 2 nodos 01:30:00; colectivas 4 asignaciones de 8 nodos
#               (02:30:00 ×3 y 02:00:00 la última), ~28 min/ronda (medido en fase A).
# Humo (QA a-h): L2a — REQUERIDO, sincronizado y revisado antes de este fichero
#               (QA a-g ✓ en el humo; h en estos ficheros).
# Dependencias: REQUIERE L2a revisado. Orden cpu112c fijado por la persona con
#               DEPENDE_DE (L1 → L5 → L6 → L2a → L2b).
# sha256 de ESTE fichero: anotado en informes/estado-lineas.md.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261006-L2b-osu112-completo-v2.sh
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
check_sha experiments/ligero112_osu.sbatch 4fd0c754f578322b8f70607babbdd625ff18cee4578c8cd7d4a7efea8ee40079
check_sha experiments/helpers/ligero36_pin.sh 6788d173ae493d8293b87c76fdc156522953407ad9ff5d48eb5601987bde280b
mkdir -p data/raw/ligero112

DEP="${DEPENDE_DE:-}"
DEPOPT=""
[ -n "$DEP" ] && DEPOPT="-d afterany:$DEP"

P="$(sbatch --parsable $DEPOPT --nodelist=b9p03,b9p04 --time=01:30:00 experiments/ligero112_osu.sbatch pt2pt)"
C1="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=02:30:00 -d afterany:$P \
      experiments/ligero112_osu.sbatch coll 1 3)"
C2="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=02:30:00 -d afterany:$C1 \
      experiments/ligero112_osu.sbatch coll 4 6)"
C3="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=02:30:00 -d afterany:$C2 \
      experiments/ligero112_osu.sbatch coll 7 9)"
C4="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=02:00:00 -d afterany:$C3 \
      experiments/ligero112_osu.sbatch coll 10 11)"
echo "L2b-v2 OSU112 lanzado: pt2pt=$P coll=$C1,$C2,$C3,$C4 (final=$C4)"
echo "Después: calcular la R2 del ligero sobre estos datos y preparar L2c (FT-8n con los pares seleccionados)."
