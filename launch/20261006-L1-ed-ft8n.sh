#!/usr/bin/env bash
# launch/20261006-L1-ed-ft8n.sh — E-d: celda ingenua frente a recomendada (8 nodos)
#
# Objetivo:     FT clase D a 8 nodos × 64 r/n (512), modo ingenuo (gcc/Open MPI por
#               defecto, Slurm elige nodos) frente a recomendado (intel/mlx, grupo
#               SMT-off, mapa explícito), 11 rondas (1 calentamiento + 10 efectivas).
# Autorización: DEVIATIONS E-d 2026-10-02, ampliación 2026-10-04 y orden alternado
#               2026-10-05 (E67). QA a-h completa (humos 83735/83736).
# Scripts:      experiments/ed_ft.sbatch — commit 76a7d8091ebb0518ce57dcb673534211f434fa95
# Estimación:   8 jobs de 8 nodos × ≤ 00:40:00, cola compartida --exclusive
#               (cada asignación: 2-3 rondas de 1 run de ~20 s + map-check + ldd +
#               controles en las recomendadas; margen amplio).
# Humo (QA a-h): 83735 (ingenuo 1 ronda) y 83736 (recomendado 1 ronda) — COMPLETED;
#               exit real 0, SUCCESSFUL + clase D, map-check por modo, ldd correcto
#               (libmpi = mpirun cargado), nodos/SMT registrados (el ingenuo cayó en
#               b9p02 SMT-on con 2 cpus/rank por defecto — dato de la prueba);
#               sincronizados y verificados (verifica_raw 0 fallos, commit dc6dece).
#               QA: a✓ b✓ c✓ (patrón SUCCESSFUL+Size D contra salida real y caso que
#               debe fallar: ft.B.x → FALLO) d✓ e✓ f✓ g✓ h (este fichero).
# Dependencias: primera de la serie cpu112c (no requiere nada previo). Propuesta de
#               orden en cpu112c: L1 → L2a → L2b → L2c → L6, con L5 (1 nodo) y los
#               jobs de 1 nodo de L7 donde no compitan.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261006-L1-ed-ft8n.sh
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"
cd "$REPO"                                   # cd explícito a la raíz del checkout (regla 10)
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="76a7d8091ebb0518ce57dcb673534211f434fa95"
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
[ "$ACTUAL" = "$EXPECTED_COMMIT" ] || { echo "!! .deploy-commit ($ACTUAL) != commit de los scripts ($EXPECTED_COMMIT)" >&2; exit 2; }
mkdir -p data/raw/infrautil

# Orden alternado (DEVIATIONS 2026-10-05): I1→R1→I2→R2→I3→R3→I4→R4, cadena afterany.
# Ingenuo: SIN --exclude (Slurm elige nodos — muestrea lo que recibe un usuario real).
# Recomendado: --exclude=b9p02,b9p12 (grupo SMT-off) + control D-B inicio/fin (en script).
I1="$(sbatch --parsable --nodes=8 --time=00:40:00 experiments/ed_ft.sbatch ingenuo 1 3)"
R1="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=00:40:00 -d afterany:$I1 experiments/ed_ft.sbatch recomendado 1 3)"
I2="$(sbatch --parsable --nodes=8 --time=00:40:00 -d afterany:$R1 experiments/ed_ft.sbatch ingenuo 4 6)"
R2="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=00:40:00 -d afterany:$I2 experiments/ed_ft.sbatch recomendado 4 6)"
I3="$(sbatch --parsable --nodes=8 --time=00:40:00 -d afterany:$R2 experiments/ed_ft.sbatch ingenuo 7 9)"
R3="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=00:40:00 -d afterany:$I3 experiments/ed_ft.sbatch recomendado 7 9)"
I4="$(sbatch --parsable --nodes=8 --time=00:40:00 -d afterany:$R3 experiments/ed_ft.sbatch ingenuo 10 11)"
R4="$(sbatch --parsable --nodes=8 --exclude=b9p02,b9p12 --time=00:40:00 -d afterany:$I4 experiments/ed_ft.sbatch recomendado 10 11)"
echo "L1 E-d lanzado: I1=$I1 R1=$R1 I2=$I2 R2=$R2 I3=$I3 R3=$R3 I4=$I4 R4=$R4 (final=$R4)"
