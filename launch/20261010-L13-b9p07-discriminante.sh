#!/usr/bin/env bash
# L13 — contraste contemporáneo b9p07 frente a b9p15 (T36, carril B).
# Autorización de preparación: informes/ordenes/2026-10-10-T36.md.
# PENDIENTE de auditoría y firma humana por SHA; T36 no despliega ni lanza.
# Ejecutará el carril A, con nueva tarea y firma; sin reservas ni privilegios.
# A = L10-A: b9p06,b9p07,b9p08,b9p09,b9p10,b9p11,b9p13,b9p16.
# C = los mismos ocho nodos sustituyendo b9p07 por b9p15 (HCA MT4123).
# Orden secuencial A1 -> C1 -> A2 -> C2 mediante --dependency=afterany.
# afterany impone orden, NO garantiza continuidad temporal: registrar esperas.
# Cada job: cpu112c, 8 nodos exclusivos, 512 ranks, 64/nodo, mapa 0-31,56-87.
# Script sin cambios: fase_b_intelc.sh ep_ft 1 4, Intel MPI + mlx,
# intel/gfortran e intelc/ifx alternados por ronda (D21).
# Cuatro rondas: 1 calentamiento + 3 efectivas, según la orden T36.
# Runs por job: EP-8n y FT-8n x 2 pares x 4 = 16 SUCCESSFUL (12 efectivos).
# Por carga/par/job: 4 runs, 3 efectivos. Total 64 NPB, 48 efectivos;
# por conjunto/carga/par: 8 runs, 6 efectivos, con calentamientos por job.
# Además 2 controles OSU allreduce 64 KiB/job (8 total), 2 map-checks/job
# (uno por par); 48 filas SALTADA/job (1/2/4n), NO son runs medidos.
# --time según T26 y fuente informes/tareas/T14/tiempos.txt:
# intel/mlx ep_ft-8n 11 rondas = 4,985567 min (jobs 83314+83405).
# 4,985567 x 2 pares x 4/11 x 1,3 + 10 = 14,713627 min -> ceil5 = 15 min.
# Reserva 4 jobs x 8 nodos x 15/60 = 8 nodo-hora (<=12).
# Referencia scripts: commit 6e08542e (hash completo EXPECTED_COMMIT).
# SHA experiments/fase_b.sh:
# e847876a2051c326d07a12a2b66d2f2c8c857a6ff7649fd5e16d4489a85de8b5
# SHA experiments/fase_b_intelc.sh:
# e23dd72335325bf59ada8f0acdec0fbd16fb28edfbf406738f1a0bbb89d80d37
# Sync futuro (carril A, --ignore-existing): data/raw/b9p07/L13/<A1|C1|A2|C2>/.
# Los scripts siguen escribiendo en scratch/cc/raw/phaseB/faseB-ep_ft-<job>;
# stdout remoto data/raw/phaseB/faseB-L13-<etiqueta>-<job>.out. Copiar también
# esos stdout a L13/<etiqueta>/, verificar hashes/conteos y transporte/mapa.
# Un fallo no se interpreta como efecto del nodo; afterany no invalida datos
# siguientes, pero la persona revisa cualquier fallo y demora antes del análisis.
# No se cancela L10-A: cancelarlo lo decide la persona.
set -euo pipefail
: "${TURGALIUM_REPO:?definir TURGALIUM_REPO en el entorno antes de ejecutar}"
cd "$TURGALIUM_REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="6e08542e2bcd25dd105903bbd746cad9729a2e96"
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
[ "$ACTUAL" = "$EXPECTED_COMMIT" ] || echo "AVISO: rigen las puertas SHA individuales; referencia=$EXPECTED_COMMIT desplegado=$ACTUAL"
check_sha() {
  local real
  real="$(sha256sum "$1" | awk '{print $1}')"
  [ "$real" = "$2" ] || { echo "!! sha256 NO coincide: $1" >&2; exit 4; }
  echo "sha256 OK: $1"
}
check_sha experiments/fase_b.sh e847876a2051c326d07a12a2b66d2f2c8c857a6ff7649fd5e16d4489a85de8b5
check_sha experiments/fase_b_intelc.sh e23dd72335325bf59ada8f0acdec0fbd16fb28edfbf406738f1a0bbb89d80d37
mkdir -p data/raw/phaseB
A="b9p06,b9p07,b9p08,b9p09,b9p10,b9p11,b9p13,b9p16"
C="b9p06,b9p08,b9p09,b9p10,b9p11,b9p13,b9p15,b9p16"
J_A1="$(sbatch --parsable --nodes=8 --nodelist="$A" --time=00:15:00 \
  --job-name=L13-A1 experiments/fase_b_intelc.sh ep_ft 1 4)"
J_C1="$(sbatch --parsable --nodes=8 --nodelist="$C" --time=00:15:00 \
  --dependency=afterany:$J_A1 --job-name=L13-C1 experiments/fase_b_intelc.sh ep_ft 1 4)"
J_A2="$(sbatch --parsable --nodes=8 --nodelist="$A" --time=00:15:00 \
  --dependency=afterany:$J_C1 --job-name=L13-A2 experiments/fase_b_intelc.sh ep_ft 1 4)"
J_C2="$(sbatch --parsable --nodes=8 --nodelist="$C" --time=00:15:00 \
  --dependency=afterany:$J_A2 --job-name=L13-C2 experiments/fase_b_intelc.sh ep_ft 1 4)"
echo "L13: A1=$J_A1 C1=$J_C1 A2=$J_A2 C2=$J_C2; sync -> data/raw/b9p07/L13/"
