#!/usr/bin/env bash
# Celdas FT del protocolo ligero de cpu36c (E-f; kernel FT fijo, clase por R8.4).
# Clase confirmada (calib36 v3, jobs 83394/83395): D es la menor con duración >= 30 s
# a 1 nodo en AMBAS pilas (gcc D≈195 s, intel D≈177-196 s; B≈3 s, C≈9 s).
# 11 rondas (1 calentamiento + 10 efectivas; DEVIATIONS 2026-09-30). 1 nodo x 32 ranks
# (FT exige potencia de 2; mapa bloques 16/paquete, DEVIATIONS 2026-10-04).
# Nivel 1 completo (D1: binding explícito + L1 sobre el representante): start/pre +
# post/stop por asignación, patrón ligero_cpu.sh.
# Uso (una celda por job, nodo representante del grupo por --nodelist):
#   sbatch --nodelist=aac102 experiments/ligero36_ft.sbatch gcc     (N1)
#   sbatch --nodelist=aac102 experiments/ligero36_ft.sbatch intel   (N2)
#   sbatch --nodelist=acc101 experiments/ligero36_ft.sbatch gcc     (N3)
#   sbatch --nodelist=acc101 experiments/ligero36_ft.sbatch intel   (N4)
#SBATCH --job-name=cc-lig36-ft
#SBATCH --exclusive
#SBATCH --partition=cpu36c
#SBATCH --nodes=1
#SBATCH --output=data/raw/ligero/%x-%j.out
#SBATCH --time=01:30:00

set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env

PILA="${1:?uso: ligero36_ft.sbatch <gcc|intel>}"
case "$PILA" in gcc|intel) ;; *) echo "!! pila desconocida: $PILA" >&2; exit 2 ;; esac
NPN=32
REP=11
CLASS=D
# Dimensiones de clase: el SUCCESSFUL de NPB no distingue la clase (hallazgo 83301/83312)
DIMS_D="2048x1024x1024"

SCRIPT_SHA="$(sha256sum "$(readlink -f "$0")" | awk '{print $1}')"
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/ligero/ft36-$PILA-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="ft36-$PILA-$SLURM_JOB_ID"
export LEVEL1_MODE="unprivileged"   # R14
W="$TURGALIUM_REPO/instrumentation/cmdlog.sh"
L1="$TURGALIUM_REPO/instrumentation/level1_capture.sh"
[ -x "$W" ] && [ -f "$L1" ] || { echo "!! falta instrumentación" >&2; exit 3; }
mkdir -p "$CMDLOG_DIR"

BIN="$TURGALIUM_SCRATCH/benchmarks/npb/$PILA/clx/ft.$CLASS.x"
[ -x "$BIN" ] || { echo "!! falta binario $BIN" >&2; exit 3; }

echo "== lig36-ft job=$SLURM_JOB_ID celda N:$PILA nodo=$(scontrol show hostname "$SLURM_JOB_NODELIST" | tr '\n' ' ')sha256=$SCRIPT_SHA $(date -Is)"

case "$PILA" in
  gcc)   module purge 2>/dev/null || true; module load openmpi_gcc/5.0.5 ucx/1.9.0
          RUN=(mpirun -np "$NPN" --map-by "ppr:$(( NPN / 2 )):package" --bind-to core) ;;
  intel) module purge 2>/dev/null || true; module load intel/2025.3.2
          export I_MPI_PIN=1 I_MPI_PIN_PROCESSOR_LIST="0-15,18-33"
          RUN=(mpirun -n "$NPN" -ppn "$NPN") ;;
esac

bash "$L1" start
bash "$L1" pre
MANIFEST="$CMDLOG_DIR/manifest.csv"
echo "job,celda,ronda,ranks,exit_code,verificacion,runlog" > "$MANIFEST"
for r in $(seq 1 "$REP"); do
  RD="$CMDLOG_DIR/r$(( 10#$r ))"; mkdir -p "$RD"
  echo "--- RUN ft.$CLASS/$PILA ronda=$r ranks=$NPN $(date -Is)"
  if bash "$W" "${RUN[@]}" "$BIN" > "$RD/run.log" 2>&1; then ec=0; else ec=$?; fi
  if [ "$ec" -eq 0 ] && grep -qE "Verification[[:space:]]*=[[:space:]]*SUCCESSFUL" "$RD/run.log" \
     && grep -q "Size.*${DIMS_D}" "$RD/run.log"; then v=SUCCESSFUL; else v=FALLO; fi
  echo "    -> exit=$ec verif=$v"
  echo "$SLURM_JOB_ID,ft-$PILA,$r,$NPN,$ec,$v,$RD/run.log" >> "$MANIFEST"
done
bash "$L1" post
bash "$L1" stop
echo "== lig36-ft $PILA terminado (job $SLURM_JOB_ID) $(date -Is) — $MANIFEST"
