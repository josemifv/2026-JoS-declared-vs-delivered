#!/usr/bin/env bash
# FT a 8 nodos del protocolo ligero de cpu36c (E-f; DEVIATIONS 2026-10-05), v3.
# Completa el ligero: OSU propio + R2 sobre esos datos + FT a 8 nodos con los pares
# que R2 selecciona. Grupos: SMT-off aac112-119; SMT-on acc112-119.
# Uso: sbatch ... experiments/ligero36_ft8n.sbatch 1 11 "gcc rc" ...
# El humo existente 83726 cubre los cuatro pares anteriores; no cubre intelc.
# (pares R2 confirmados por la persona; la puntuación R2 usó SOLO pares intra-switch,
# el cruzado va aparte — D2/E-b)
# FT clase D a 256 ranks (8×32, potencia de 2), mapa bloques 16/paquete.
# Humo: 5 runs (1 ronda, cinco pares); medida: 2 grupos × 11 rondas × 5 pares = 110,
# más controles D-B al inicio y fin.
# (osu_allreduce -m 65536, gcc por defecto). Verificación por run: Size clase D +
# "Verification = SUCCESSFUL". Instrumentación como la matriz de fase B: sin JSON de
# nivel 1 (DEVIATIONS 2026-10-05).
#SBATCH --job-name=cc-lig36-ft8n
#SBATCH --exclusive
#SBATCH --partition=cpu36c
#SBATCH --nodes=8
#SBATCH --output=data/raw/ligero/%x-%j.out
#SBATCH --time=01:00:00

set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env

R_FROM="${1:?uso: ligero36_ft8n.sbatch <r_from> <r_to> <pila transporte> [pares...]}"
R_TO="${2:?falta r_to}"; shift 2
[ $# -gt 0 ] || { echo "!! faltan los pares R2 (p. ej. \"gcc rc\" \"intelc mlx\" ...)" >&2; exit 2; }
PAIRS=("$@")
[ "$SLURM_JOB_NUM_NODES" = 8 ] || { echo "!! ft8n requiere 8 nodos" >&2; exit 3; }
NPN=32
NT=$(( SLURM_JOB_NUM_NODES * NPN ))
DIMS_D="2048x1024x1024"
COMBOS=()   # validación: los pares deben ser de la forma <pila> <transporte>
for p in "${PAIRS[@]}"; do set -- $p; case "$1" in gcc|intel|intelc) ;; *) echo "!! pila desconocida: $1" >&2; exit 2;; esac; COMBOS+=("$1 $2"); done

REPO_COMMIT="$(awk '{print $1}' .deploy-commit 2>/dev/null || true)"
# 3ª auditoría (1c): el despliegue escribe el hash COMPLETO de rev-parse HEAD;
# se valida el formato y, si no cumple, se cae al git del clon o a "desconocido"
echo "$REPO_COMMIT" | grep -qE '^[0-9a-f]{7,40}$' || REPO_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo 'desconocido (clon no alineado)')"
SCRIPT_SHA="$(sha256sum "$(readlink -f "$0")" | awk '{print $1}')"
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/ligero/ft8n-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="ft8n-$SLURM_JOB_ID"
export LEVEL1_MODE="unprivileged"   # R14 (sin JSON L1: decisión de fase B, DEVIATIONS)
CMDLOG="$TURGALIUM_REPO/instrumentation/cmdlog.sh"
[ -x "$CMDLOG" ] || { echo "!! falta wrapper $CMDLOG" >&2; exit 3; }
mkdir -p "$CMDLOG_DIR"

BIN_OF() { echo "$TURGALIUM_SCRATCH/benchmarks/npb/$1/clx/ft.D.x"; }
for p in "${PAIRS[@]}"; do set -- $p; [ -x "$(BIN_OF "$1")" ] || { echo "!! falta $(BIN_OF "$1")" >&2; exit 3; }; done

echo "== ft8n job=$SLURM_JOB_ID pares=${PAIRS[*]} rondas=$R_FROM..$R_TO sha256=$SCRIPT_SHA $(date -Is)"
echo "== nodos asignados (fijos dentro de la asignación):"
srun --ntasks="$SLURM_JOB_NUM_NODES" --ntasks-per-node=1 hostname -s | sort | tr '\n' ' '; echo

env_par() { # $1 = pila; $2 = transporte (mismas convenciones que ligero36_osu)
  case "$1" in
    gcc)   module purge 2>/dev/null || true; module load openmpi_gcc/5.0.5 ucx/1.9.0
           export OMPI_MCA_pml=ucx UCX_LOG_LEVEL=info I_MPI_PIN=0
           if [ "$2" = tcp ]; then
               export UCX_TLS="tcp,sm,self" OMPI_MCA_opal_common_ucx_tls=any OMPI_MCA_opal_common_ucx_devices=any
           else
               export UCX_TLS="$2,sm,self"
           fi
           unset I_MPI_FABRICS FI_PROVIDER I_MPI_DEBUG I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true ;;
    intel|intelc) module purge 2>/dev/null || true; module load intel/2025.3.2
           export I_MPI_FABRICS=ofi FI_PROVIDER="$2" I_MPI_DEBUG=5
           # Mapa en bloques de 16/paquete (0-15 socket0, 18-33 socket1), IGUAL que
           # coll:intel de ligero36_osu.sbatch. En 83494/83495 faltaba esta lista:
           # los ranks intel corrieron con cpus=0-35 (sin pin; hallazgo auditoría
           # 2026-10-05, DEVIATIONS) — celdas intel de esos jobs a revaluar.
           export I_MPI_PIN=1 I_MPI_PIN_PROCESSOR_LIST="0-15,18-33"
           unset OMPI_MCA_pml UCX_TLS UCX_LOG_LEVEL OMPI_MCA_opal_common_ucx_tls OMPI_MCA_opal_common_ucx_devices 2>/dev/null || true ;;
  esac
}

transport_label() { # $1 = pila; $2 = run.log (|| true: pipefail, patrón fase_b)
  case "$1" in
    gcc)   grep -oE 'inter-node cfg#[0-9]+ tag\([a-z_0-9/]+' "$2" | grep -oE 'tag\(.*' | sort -u | tr '\n' ' ' || true ;;
    intel|intelc) grep -m1 -oE 'libfabric provider[:= ]*[a-z_]+' "$2" | head -1 || true ;;
  esac
}

control_cell() { # $1 = inicio|fin (D-B: allreduce 64 KiB, gcc por defecto)
  module purge 2>/dev/null || true; module load openmpi_gcc/5.0.5 ucx/1.9.0
  unset OMPI_MCA_pml UCX_TLS UCX_LOG_LEVEL OMPI_MCA_opal_common_ucx_tls OMPI_MCA_opal_common_ucx_devices 2>/dev/null || true
  unset I_MPI_FABRICS FI_PROVIDER I_MPI_DEBUG I_MPI_PIN I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true
  echo "--- control D-B ($1): osu_allreduce -m 65536 ($NT ranks, gcc por defecto)"
  if ! bash "$CMDLOG" mpirun -np "$NT" --map-by "ppr:$(( NPN / 2 )):package" --bind-to core \
        "$TURGALIUM_SCRATCH/benchmarks/osu/gcc/clx/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce" -m 65536 \
      > "$CMDLOG_DIR/control-$1.log" 2>&1; then
    echo "!! FALLO control $1 (conservado en control-$1.log)"
  fi
}

MAPCHECK='echo "$(hostname -s) rank=${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-${SLURM_PROCID:-NA}}} cpus=$(taskset -pc $$ | awk "{print \$NF}")"'
map_check() { # $1 = pila; $2 = transporte
  env_par "$1" "$2"
  case "$1" in
    gcc)   mpirun -np "$NT" --map-by "ppr:$(( NPN / 2 )):package" --bind-to core bash -c "$MAPCHECK" ;;
    intel|intelc) mpirun -n "$NT" -ppn "$NPN" bash -c "$MAPCHECK" ;;
  esac > "$CMDLOG_DIR/mapcheck-$1-$2.txt" 2>&1 || echo "!! map-check FALLO $1/$2 (conservado)"
  echo "   map-check $1/$2: $(grep -c 'cpus=' "$CMDLOG_DIR/mapcheck-$1-$2.txt" || echo 0) ranks"
}

MANIFEST="$CMDLOG_DIR/manifest.csv"
echo "job,ronda,par,ranks,exit_code,verificacion,transporte,runlog" > "$MANIFEST"

run_ft() { # $1 = pila; $2 = transporte; $3 = ronda
  local pila="$1" trans="$2" ronda="$3" ec verif lbl bin
  bin="$(BIN_OF "$pila")"
  local rundir="$CMDLOG_DIR/ft-$pila-$trans-r$(( 10#$ronda ))"
  mkdir -p "$rundir"
  echo "--- RUN ft.D par=$pila/$trans ronda=$ronda ranks=$NT $(date -Is)"
  env_par "$pila" "$trans"
  # v2 (auditoría 2026-10-05): el patrón `if ! cmd; then ec=$?` daba SIEMPRE ec=0
  # (dentro del then, $? es el estado del pipeline NEGADO, 0 cuando cmd falla).
  case "$pila" in
    gcc)   if bash "$CMDLOG" mpirun -np "$NT" --map-by "ppr:$(( NPN / 2 )):package" --bind-to core "$bin" \
               > "$rundir/run.log" 2>&1; then ec=0; else ec=$?; fi ;;
    intel|intelc) if bash "$CMDLOG" mpirun -n "$NT" -ppn "$NPN" "$bin" \
               > "$rundir/run.log" 2>&1; then ec=0; else ec=$?; fi ;;
  esac
  if [ "$ec" -eq 0 ] && grep -qE "Verification[[:space:]]*=[[:space:]]*SUCCESSFUL" "$rundir/run.log" \
     && grep -q "Size.*${DIMS_D}" "$rundir/run.log"; then verif=SUCCESSFUL; else verif=FALLO; fi
  lbl="$(transport_label "$pila" "$rundir/run.log")"; lbl="${lbl:-sin-observar}"
  echo "    -> exit=$ec verif=$verif transporte=$lbl"
  echo "$SLURM_JOB_ID,$ronda,$pila/$trans,$NT,$ec,$verif,$lbl,$rundir/run.log" >> "$MANIFEST"
}

control_cell inicio
for p in "${PAIRS[@]}"; do set -- $p; map_check "$1" "$2"; done
for r in $(seq "$R_FROM" "$R_TO"); do
  echo "== RONDA $r $(date -Is)"
  for p in "${PAIRS[@]}"; do set -- $p; run_ft "$1" "$2" "$r"; done
done
control_cell fin
echo "== ft8n ($R_FROM..$R_TO) terminado (job $SLURM_JOB_ID) $(date -Is)"
echo "== manifiesto: $MANIFEST"
