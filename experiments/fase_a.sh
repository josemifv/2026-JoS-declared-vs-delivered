#!/usr/bin/env bash
# Fase A (plan v2.1 + aprobaciones del 2026-10-03, §16): bloque pt2pt o colectivas.
# Verificación funcional integrada (humo por par dentro de la asignación), 11 rondas
# intercaladas (la 1.ª es calentamiento), mapa explícito por pila verificado por run
# (R10), transporte efectivo registrado por run (nivel 1), celda de control al inicio
# y al final de la asignación, tope de colectivas en 256 KiB.
#
# Aprobaciones aplicadas (rules/DEVIATIONS.md, 2026-10-03):
#  - Nodos cualesquiera del grupo SMT-off, fijos dentro de la asignación (sin --nodelist).
#  - OMPI_MCA_opal_common_ucx_tls/devices=any SOLO en el par gcc/tcp (lista blanca del
#    pml ucx: aviso de configuración de Open MPI, no discrepancia declarado/real).
#  - alltoall gcc/tcp a 512 ranks NO MEDIBLE en modo usuario (P-4): no se ejecuta.
#
# Uso (desde la raíz del checkout del repo en el clúster):
#   sbatch --nodes=2 --exclude=b9p02,b9p12 --time=02:00:00 experiments/fase_a.sh pt2pt
#   sbatch --nodes=8 --exclude=b9p02,b9p12 --time=03:00:00 experiments/fase_a.sh colectivas
#SBATCH --job-name=cc-faseA
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --time=02:00:00
#SBATCH --output=data/raw/phaseA/faseA-%x-%j.out

set -uo pipefail
source clusters/local.env
PARTE="${1:?parte: pt2pt|colectivas}"
# Rango de rondas de esta asignacion (P-5: asignaciones de rondas completas; por defecto 1..11).
R_FROM="${2:-1}"; R_TO="${3:-11}"
NPN=64
ROUNDS=11
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/phaseA/faseA-$PARTE-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="faseA-$PARTE-$SLURM_JOB_ID"
export LEVEL1_MODE="unprivileged"   # R14, registrado en clusters/turgalium.md
CMDLOG="instrumentation/cmdlog.sh"
OSU_GCC="$TURGALIUM_SCRATCH/benchmarks/osu/gcc/libexec/osu-micro-benchmarks/mpi"
OSU_INTEL="$TURGALIUM_SCRATCH/benchmarks/osu/intel/libexec/osu-micro-benchmarks/mpi"
# Mapa pedido de colectivas: 32 en bloque por socket; NUMA node0 = CPUs 0-55, node1 = 56-111.
MAP64="$(seq -s, 0 31),$(seq -s, 56 87)"
MAPCHECK='echo "$(hostname -s) rank=${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-${SLURM_PROCID:-NA}}} cpus=$(taskset -pc $$ | awk "{print \$NF}")"'

mkdir -p "$CMDLOG_DIR" data/raw/phaseA
echo "== job $SLURM_JOB_ID ($PARTE) inicia $(date -Is)"
echo "== nodos asignados (fijos dentro de la asignación):"
srun --ntasks="$SLURM_JOB_NUM_NODES" --ntasks-per-node=1 hostname -s | sort | tr '\n' ' '; echo

# HCA e interfaces por nodo (sysfs sin privilegios).
nodo_info() {
  srun --ntasks="$SLURM_JOB_NUM_NODES" --ntasks-per-node=1 bash -c '
    echo "== nodo $(hostname -s)";
    for d in /sys/class/infiniband/mlx5_*; do
      [ -d "$d" ] || continue
      nn=$(cat "$d/device/numa_node" 2>/dev/null || echo NA)
      rt=$(cat "$d/ports/1/rate" 2>/dev/null || echo NA)
      echo "  HCA $(basename "$d") numa_node=$nn rate=$rt"
    done
    ip -o -4 addr show | awk "{print \"  IFACE \" \$2 \" \" \$4}"' 2>&1
}

elige_map1() {
  first="$(printf '%s\n' "$1" | grep -a 'rate=200' | head -1 | sed -n 's/.*numa_node=\([0-9-]*\).*/\1/p')"
  case "$first" in
    0) echo 0 ;;
    1) echo 56 ;;
    *) echo "AVISO-NUMA:no-determinable" ;;
  esac
}

# Lanzador por pila con el MISMO mapa explícito para ambas (§Binding AGENTS.md;
# fallback verificado en los humos: srun no puede aplicar --cpu-bind, TaskPlugin=(null)):
#   gcc:   mpirun (Open MPI): pt2pt ppr:1:node; colectivas ppr:32:package; --bind-to core
#   intel: mpirun (Hydra) -n/-ppn + I_MPI_PIN_PROCESSOR_LIST (colectivas 0-31,56-87; pt2pt 0)
launch_setup() { # $1 = pila; $2 = ntasks; $3 = ranks por nodo
  case "$1" in
    gcc)   if [ "$3" = 1 ]; then MAPBY="ppr:1:node"; else MAPBY="ppr:$(( $3 / 2 )):package"; fi
           LAUNCH=(mpirun -np "$2" --map-by "$MAPBY" --bind-to core) ;;
    intel) if [ "$3" = 1 ]; then export I_MPI_PIN_PROCESSOR_LIST="0"
           else export I_MPI_PIN_PROCESSOR_LIST="0-31,56-87"; fi
           LAUNCH=(mpirun -n "$2" -ppn "$3") ;;
  esac
}

# Entorno por par. Lista blanca a "any" SOLO en gcc/tcp (DEVIATIONS 2026-10-03).
env_par() { # $1 = pila; $2 = transporte
  case "$1" in
    gcc)   module purge 2>/dev/null || true; module load openmpi_gcc/5.0.5 ucx/1.9.0
           export OMPI_MCA_pml=ucx UCX_TLS="${2},sm,self" UCX_LOG_LEVEL=info
           unset I_MPI_FABRICS FI_PROVIDER FI_TCP_IFACE I_MPI_DEBUG I_MPI_PMI_LIBRARY I_MPI_PIN_PROCESSOR_LIST
           if [ "$2" = tcp ]; then
             export UCX_NET_DEVICES="$TCP_IFACE"
             export OMPI_MCA_opal_common_ucx_tls=any OMPI_MCA_opal_common_ucx_devices=any
           else
             unset UCX_NET_DEVICES OMPI_MCA_opal_common_ucx_tls OMPI_MCA_opal_common_ucx_devices
           fi ;;
    intel) module purge 2>/dev/null || true; module load intel/2025.3.2
           export I_MPI_FABRICS=ofi FI_PROVIDER="$2" I_MPI_DEBUG=5
           unset OMPI_MCA_pml UCX_TLS UCX_LOG_LEVEL UCX_NET_DEVICES OMPI_MCA_opal_common_ucx_tls OMPI_MCA_opal_common_ucx_devices
           [ "$2" = tcp ] && export FI_TCP_IFACE="$TCP_IFACE" ;;
  esac
}

map_check() { # $1 = etiqueta; usa LAUNCH del launch_setup previo
  echo "--- map-check $1 (pedido: ${MAPPED})"
  "${LAUNCH[@]}" bash -c "$MAPCHECK" || echo "!! map-check FALLO $1"
}

run_par() { # pila trans osu_dir tbin [args]; envía un run registrado (cmdlog + hash)
  local pila="$1" trans="$2" osudir="$3" tbin="$4"
  shift 4
  env_par "$pila" "$trans"
  bash "$CMDLOG" "${LAUNCH[@]}" "$osudir/$tbin" "$@" || echo "!! FALLO $pila/$trans $tbin $*"
}

# Celda de control (D-B): gcc, transporte por defecto, allreduce 64 KiB, sobre los
# nodos de la asignación; se repite al inicio y al final (DEVIATIONS 2026-10-03).
control_cell() { # $1 = inicio|fin
  module purge 2>/dev/null || true; module load openmpi_gcc/5.0.5 ucx/1.9.0
  unset OMPI_MCA_pml UCX_TLS UCX_NET_DEVICES OMPI_MCA_opal_common_ucx_tls OMPI_MCA_opal_common_ucx_devices
  unset I_MPI_FABRICS FI_PROVIDER FI_TCP_IFACE I_MPI_DEBUG I_MPI_PMI_LIBRARY I_MPI_PIN_PROCESSOR_LIST
  export UCX_LOG_LEVEL=info
  local NT=$((SLURM_JOB_NUM_NODES * NPN))
  echo "--- control D-B ($1): osu_allreduce -m 65536 ($NT ranks, gcc por defecto)"
  launch_setup gcc "$NT" "$NPN"
  bash "$CMDLOG" "${LAUNCH[@]}" "$OSU_GCC/collective/osu_allreduce" -m 65536 || echo "!! FALLO control $1"
}

TCP_IFACE="$(ip -o -4 addr show | awk '$2 ~ /^(ib|ibs)/ {print $2; exit}')"
[ -n "${TCP_IFACE:-}" ] || TCP_IFACE="$(ip -o -4 addr show | awk '$2 != "lo" {print $2; exit}')"
echo "== interfaz tcp fijada: $TCP_IFACE (igual en ambas pilas)"

INFO="$(nodo_info)"
echo "$INFO"
MAP1="$(elige_map1 "$INFO")"
case "$MAP1" in 0|56) ;; *) echo "AVISO: MAP1 no determinado ($MAP1); se usa core 0 y se declara"; MAP1=0 ;; esac
echo "== core pt2pt (primer core del dominio NUMA del HCA): $MAP1"

# Orden a priori del plan §6: gcc rc, dc, ud, tcp; intel mlx, verbs, tcp.
PAIRS=( "gcc rc" "gcc dc" "gcc ud" "gcc tcp" "intel mlx" "intel verbs" "intel tcp" )

case "$PARTE" in
  pt2pt)
    MAPPED="$MAP1"
    control_cell inicio
    # Verificación funcional por par (transporte + mapa R10): osu_latency acotado.
    for p in "${PAIRS[@]}"; do
      set -- $p
      osudir="$OSU_GCC/pt2pt"; [ "$1" = intel ] && osudir="$OSU_INTEL/pt2pt"
      env_par "$1" "$2"
      launch_setup "$1" 2 1
      map_check "humo-$1/$2"
      run_par "$1" "$2" "$osudir" osu_latency -m 8192
    done
    # 11 rondas intercaladas: ronda k = repetición k de las 21 celdas.
    for r in $(seq "$R_FROM" "$R_TO"); do
      echo "== RONDA $r/$ROUNDS $(date -Is)"
      for p in "${PAIRS[@]}"; do
        set -- $p
        osudir="$OSU_GCC/pt2pt"; [ "$1" = intel ] && osudir="$OSU_INTEL/pt2pt"
        launch_setup "$1" 2 1
        run_par "$1" "$2" "$osudir" osu_latency -m 8:4194304
        run_par "$1" "$2" "$osudir" osu_bw      -m 8:4194304
        run_par "$1" "$2" "$osudir" osu_bibw    -m 8:4194304
      done
    done
    control_cell fin
    ;;
  colectivas)
    MAPPED="$MAP64"
    control_cell inicio
    NT=$((SLURM_JOB_NUM_NODES * NPN))
    # Verificación funcional por par (transporte + mapa R10): allreduce acotado.
    for p in "${PAIRS[@]}"; do
      set -- $p
      env_par "$1" "$2"
      launch_setup "$1" "$NT" "$NPN"
      map_check "humo-$1/$2"
      osudir="$OSU_GCC/collective"; [ "$1" = intel ] && osudir="$OSU_INTEL/collective"
      run_par "$1" "$2" "$osudir" osu_allreduce -m 1024
    done
    # 11 rondas intercaladas: ronda k = repetición k de las 13 celdas
    # (alltoall gcc/tcp NO MEDIBLE: P-4, no se ejecuta).
    for r in $(seq "$R_FROM" "$R_TO"); do
      echo "== RONDA $r/$ROUNDS $(date -Is)"
      for p in "${PAIRS[@]}"; do
        set -- $p
        osudir="$OSU_GCC/collective"; [ "$1" = intel ] && osudir="$OSU_INTEL/collective"
        launch_setup "$1" "$NT" "$NPN"
        run_par "$1" "$2" "$osudir" osu_allreduce -m 262144
        if ! { [ "$1" = gcc ] && [ "$2" = tcp ]; }; then
          run_par "$1" "$2" "$osudir" osu_alltoall -m 262144
        fi
      done
    done
    control_cell fin
    ;;
  *) echo "parte desconocida: $PARTE" >&2; exit 2 ;;
esac
echo "== fase A $PARTE terminada (job $SLURM_JOB_ID) $(date -Is); registro en $CMDLOG_DIR"
