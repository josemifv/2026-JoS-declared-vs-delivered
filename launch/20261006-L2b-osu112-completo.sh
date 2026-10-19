#!/usr/bin/env bash
# launch/20261006-L2b-osu112-completo.sh — OSU COMPLETO del protocolo ligero
# INDEPENDIENTE de cpu112c (D18): pt2pt + colectivas de los 7 pares.
#
# Objetivo:     Datos OSU propios del ligero para la R2 del D18: pt2pt (latency/bw,
#               8 B–4 MiB, UN par intra-switch: b9p03↔b9p04) y colectivas
#               (allreduce/alltoall ≤ 256 KiB, 8 nodos SMT-off × 64 r/n),
#               11 rondas intercaladas (1 calentamiento + 10 efectivas), control
#               D-B al inicio y fin de cada asignación.
# Autorización: DEVIATIONS 2026-10-06 D18; rangos de 2026-10-03 (fase A); P-2/P-5
#               (asignaciones de rondas completas ≤ 3 h); 0b (verificación funcional).
# Scripts:      experiments/ligero112_osu.sbatch — commit 76a7d8091ebb0518ce57dcb673534211f434fa95
# Estimación:   5 jobs: pt2pt 2 nodos 01:30:00 (7 pares × 11 rondas ≈ 30-60 min);
#               colectivas 4 asignaciones de 8 nodos × 02:30:00 (3 rondas c/u,
#               ~28 min/ronda medida en fase A a 512 ranks) + la última 02:00:00 (2 rondas).
# Humo (QA a-h): L2a (verif112 + coll 1 ronda + ft8n 1 ronda) — REQUERIDO y revisado
#               antes de lanzar este fichero. QA: a✓ (misma forma/tamaño: pt2pt 2n
#               en verif; coll 8n×512r en el humo) b✓ (map-check por combo + transporte
#               observado + ldd) c✓ (patrón # OSU MPI contra salida real del humo;
#               caso que debe fallar: ft.B.x, FALLO ✓) d✓ (exit real en manifiesto)
#               e✓ (trazado a D18/P-2/P-5) f✓ (salida del humo presentada) g✓ (sync +
#               verifica_raw por job) h✓ (fichero aprobado por sha256).
# Dependencias: REQUIERE el humo L2a COMPLETADO, sincronizado y REVISADO por la
#               persona. En cpu112c va tras L1; L6 (anclas) tras L2b/L2c.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261006-L2b-osu112-completo.sh
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"
cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="76a7d8091ebb0518ce57dcb673534211f434fa95"
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
[ "$ACTUAL" = "$EXPECTED_COMMIT" ] || { echo "!! .deploy-commit ($ACTUAL) != commit de los scripts ($EXPECTED_COMMIT)" >&2; exit 2; }
mkdir -p data/raw/ligero112

# pt2pt completo (1 par intra-switch; 11 rondas; el job es corto)
P="$(sbatch --parsable --nodelist=b9p03,b9p04 --time=01:30:00 experiments/ligero112_osu.sbatch pt2pt)"
# colectivas en asignaciones de rondas completas (P-5), cadena afterany
C1="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=02:30:00 -d afterany:$P \
      experiments/ligero112_osu.sbatch coll 1 3)"
C2="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=02:30:00 -d afterany:$C1 \
      experiments/ligero112_osu.sbatch coll 4 6)"
C3="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=02:30:00 -d afterany:$C2 \
      experiments/ligero112_osu.sbatch coll 7 9)"
C4="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=02:00:00 -d afterany:$C3 \
      experiments/ligero112_osu.sbatch coll 10 11)"
echo "L2b OSU112 lanzado: pt2pt=$P coll=$C1,$C2,$C3,$C4 (final=$C4)"
echo "Después de este bloque: calcular R2 del ligero sobre estos datos y preparar L2c (FT-8n con los pares seleccionados)."
