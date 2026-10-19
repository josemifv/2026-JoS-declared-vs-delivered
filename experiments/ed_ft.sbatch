#!/usr/bin/env bash
# E-d: celda ingenua frente a celda recomendada (DEVIATIONS 2026-10-02 E-d y 2026-10-04
# ampliación). FT clase D a 8 nodos × 64 ranks = 512 (potencia de 2), binarios spr.
#   Modo INGENUO (lo que recibe un usuario que se fía de lo declarado):
#     GCC + Open MPI 5.0.5 con TODO por defecto (sin UCX_TLS, sin mapeo ni binding;
#     Open MPI aplica su política por defecto y el mapa real se registra, R10),
#     `mpirun -np 512`, jobs INDEPENDIENTES de 8 nodos SIN --exclude (Slurm elige):
#     las rondas se reparten 3/3/3/2 en cuatro asignaciones para muestrear nodos.
#   Modo RECOMENDADO (según la ficha de ejecución):
#     pila y transporte de R2 (intel/mlx), grupo SMT-off (--exclude=b9p02,b9p12),
#     mapa explícito en bloques de 32/paquete (I_MPI_PIN_PROCESSOR_LIST), UNA
#     asignación con las 11 rondas y control D-B al inicio y al fin.
# 11 rondas totales (1 calentamiento + 10 efectivas); ingenuo y recomendado en el
# mismo bloque temporal (cadena afterok el mismo día).
# Por asignación se registra: nodos asignados, SMT (lscpu) y grupos de switch.
# Nivel 1 por asignación (unprivileged, R14); verificación por run: SUCCESSFUL + clase D.
# 3ª auditoría (bloque C): map-check POR MODO (la colocación es el OBJETO de la
# prueba: se registra la del ingenuo por defecto y la del recomendado explícita)
# y ldd por modo (libmpi del binario = la del mpirun cargado). El orden de
# asignaciones ya queda alternado ingenuo/recomendado (DEVIATIONS 2026-10-05).
# Uso (crear el dir de salida ANTES: el .out lo abre slurmctld al enviar):
#   mkdir -p data/raw/infrautil
#   sbatch --nodes=8 --time=00:40:00 experiments/ed_ft.sbatch ingenuo 1 3
#   sbatch --nodes=8 --exclude=b9p02,b9p12 --time=00:40:00 experiments/ed_ft.sbatch recomendado 1 11
#SBATCH --job-name=cc-ed-ft
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --nodes=8
#SBATCH --output=data/raw/infrautil/%x-%j.out
#SBATCH --time=00:40:00

set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env

MODE="${1:?uso: ed_ft.sbatch <ingenuo|recomendado> <r_from> <r_to>}"
R_FROM="${2:?falta r_from}"; R_TO="${3:?falta r_to}"
[ "$SLURM_JOB_NUM_NODES" = 8 ] || { echo "!! E-d requiere 8 nodos" >&2; exit 3; }
NPN=64
NT=$(( SLURM_JOB_NUM_NODES * NPN ))
DIMS_D="2048x1024x1024"

REPO_COMMIT="$(awk '{print $1}' .deploy-commit 2>/dev/null || true)"
# 3ª auditoría (1c): el despliegue escribe el hash COMPLETO de rev-parse HEAD;
# se valida el formato y, si no cumple, se cae al git del clon o a "desconocido"
echo "$REPO_COMMIT" | grep -qE '^[0-9a-f]{7,40}$' || REPO_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo 'desconocido (clon no alineado)')"
SCRIPT_SHA="$(sha256sum "$(readlink -f "$0")" | awk '{print $1}')"
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/infrautil/ed-$MODE-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="ed-$MODE-$SLURM_JOB_ID"
export LEVEL1_MODE="unprivileged"   # R14
CMDLOG="$TURGALIUM_REPO/instrumentation/cmdlog.sh"
L1="$TURGALIUM_REPO/instrumentation/level1_capture.sh"
[ -x "$CMDLOG" ] && [ -f "$L1" ] || { echo "!! falta instrumentación" >&2; exit 3; }
mkdir -p "$CMDLOG_DIR"

# FT es NPB: se compila POR PILA. v2 (auditoría 2026-10-05): el modo recomendado
# corre con Intel MPI y usaba el binario de gcc (enlazado a Open MPI) — el binario
# es del modo, no siempre el de gcc.
if [ "$MODE" = recomendado ]; then BIN="$TURGALIUM_SCRATCH/benchmarks/npb/intel/spr/ft.D.x"
else BIN="$TURGALIUM_SCRATCH/benchmarks/npb/gcc/spr/ft.D.x"; fi
[ -x "$BIN" ] || { echo "!! falta binario $BIN" >&2; exit 3; }

echo "== E-d job=$SLURM_JOB_ID modo=$MODE rondas=$R_FROM..$R_TO sha256=$SCRIPT_SHA $(date -Is)"
echo "== nodos asignados (dato del modo ingenuo; fijos dentro de la asignación):"
srun --ntasks="$SLURM_JOB_NUM_NODES" --ntasks-per-node=1 bash -c \
     'echo "$(hostname -s) SMT=$(lscpu | awk "/Thread\(s\) per core/ {print \$4}")"' | sort | tr '\n' ' '; echo

PAIR_LABEL="?"
case "$MODE" in
  ingenuo)    PAIR_LABEL="gcc/default"
              module purge 2>/dev/null || true
              module load openmpi_gcc/5.0.5 ucx/1.9.0
              # TODO por defecto: sin UCX_TLS, sin OMPI_MCA_pml, sin mapa ni binding
              unset UCX_TLS UCX_LOG_LEVEL OMPI_MCA_pml I_MPI_FABRICS FI_PROVIDER I_MPI_DEBUG I_MPI_PIN I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true
              LAUNCH=(mpirun -np "$NT") ;;
  recomendado) PAIR_LABEL="intel/mlx"
              module purge 2>/dev/null || true
              module load intel/2025.3.2
              export I_MPI_FABRICS=ofi FI_PROVIDER=mlx I_MPI_DEBUG=5
              export I_MPI_PIN=1 I_MPI_PIN_PROCESSOR_LIST="$(seq -s, 0 31),$(seq -s, 56 87)"
              LAUNCH=(mpirun -n "$NT" -ppn "$NPN") ;;
  *) echo "!! modo desconocido: $MODE" >&2; exit 2 ;;
esac

# 3ª auditoría (bloque C): map-check y ldd POR MODO, antes de las rondas
MAPCHECK='echo "$(hostname -s) rank=${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-${SLURM_PROCID:-NA}}} cpus=$(taskset -pc $$ | awk "{print \$NF}")"'
echo "--- map-check $MODE (colocación: objeto de la prueba)"
"${LAUNCH[@]}" bash -c "$MAPCHECK" > "$CMDLOG_DIR/mapcheck-$MODE.txt" 2>&1 \
  || echo "!! map-check FALLO $MODE (conservado)"
echo "   ranks con cpus= : $(grep -c 'cpus=' "$CMDLOG_DIR/mapcheck-$MODE.txt" || echo 0)"
echo "--- ldd $MODE (QA 7b: libmpi del binario = la del mpirun cargado)"
ldd "$BIN" > "$CMDLOG_DIR/ldd-$MODE.txt" 2>&1 || true
grep -E "libmpi|libucp|libfabric" "$CMDLOG_DIR/ldd-$MODE.txt" || echo "!! ldd $MODE sin libmpi/ucp/fabric"

control_cell() { # $1 = inicio|fin — solo recomendado (D-B)
  [ "$MODE" = recomendado ] || return 0
  echo "--- control D-B ($1): osu_allreduce -m 65536 ($NT ranks, gcc por defecto)"
  if ! ( module purge 2>/dev/null || true; module load openmpi_gcc/5.0.5 ucx/1.9.0; \
         unset OMPI_MCA_pml UCX_TLS UCX_LOG_LEVEL 2>/dev/null || true; \
         bash "$CMDLOG" mpirun -np "$NT" --map-by "ppr:$(( NPN / 2 )):package" --bind-to core \
           "$TURGALIUM_SCRATCH/benchmarks/osu/gcc/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce" -m 65536 \
           > "$CMDLOG_DIR/control-$1.log" 2>&1 ); then
    echo "!! FALLO control $1 (conservado)"
  fi
}

MANIFEST="$CMDLOG_DIR/manifest.csv"
echo "job,modo,ronda,celda,par,ranks,exit_code,verificacion,runlog" > "$MANIFEST"
bash "$L1" start
bash "$L1" pre
control_cell inicio
for r in $(seq "$R_FROM" "$R_TO"); do
  echo "== RONDA $r $(date -Is)"
  RD="$CMDLOG_DIR/r$(( 10#$r ))"; mkdir -p "$RD"
  if bash "$CMDLOG" "${LAUNCH[@]}" "$BIN" > "$RD/run.log" 2>&1; then ec=0; else ec=$?; fi
  if [ "$ec" -eq 0 ] && grep -qE "Verification[[:space:]]*=[[:space:]]*SUCCESSFUL" "$RD/run.log" \
     && grep -q "Size.*${DIMS_D}" "$RD/run.log"; then v=SUCCESSFUL; else v=FALLO; fi
  echo "    -> exit=$ec verif=$v"
  echo "$SLURM_JOB_ID,$MODE,$r,ft-8n,$PAIR_LABEL,$NT,$ec,$v,$RD/run.log" >> "$MANIFEST"
done
control_cell fin
bash "$L1" post
bash "$L1" stop
echo "== E-d $MODE ($R_FROM..$R_TO) terminado (job $SLURM_JOB_ID) $(date -Is) — $MANIFEST"
