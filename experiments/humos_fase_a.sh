#!/usr/bin/env bash
# Humos de la fase A (v2.1, segundo pase): transporte efectivo por par, mapa
# pedido = mapa real (R10), NUMA del HCA, interfaz tcp y duración de UNA rep de
# colectivas con tcp (rango completo 8 B–256 KiB). NO ejecuta rondas de la fase A.
#
# Hallazgos de humos previos (83153-83156, declarado/real en el informe): srun
# NO puede aplicar --cpu-bind en este clúster (TaskPlugin=(null): sin plugin de
# afinidad); el plugin "pmix" de srun no carga (el listado ofrece "pmix_v3"); y
# OMPI 5 no acepta el calificador "socket" de --map-by ppr (es "package").
# El binding NO se delega al runtime a ciegas: se lanza con el mpirun de cada
# pila usando opciones que producen el MISMO mapa explícito (fallback del §4 del
# plan), y el mapa real se verifica por rank antes de cada prueba (R10).
#
# Uso (desde la raíz del checkout del repo en el clúster):
#   sbatch --nodes=2 --exclude=b9p02,b9p12 --time=00:15:00 experiments/humos_fase_a.sh pt2pt
#   sbatch --nodes=8 --exclude=b9p02,b9p12 --time=00:20:00 experiments/humos_fase_a.sh colectivas
#SBATCH --job-name=cc-humoA
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --time=00:20:00
#SBATCH --output=data/raw/phaseA/humos-%x-%j.out

set -uo pipefail
source clusters/local.env
PARTE="${1:?parte: pt2pt|colectivas}"
NPN=64
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/phaseA/humos-$PARTE-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="humoA-$PARTE-$SLURM_JOB_ID"
export LEVEL1_MODE="unprivileged"   # R14, registrado en clusters/turgalium.md
CMDLOG="instrumentation/cmdlog.sh"
OSU_GCC="$TURGALIUM_SCRATCH/benchmarks/osu/gcc/libexec/osu-micro-benchmarks/mpi"
OSU_INTEL="$TURGALIUM_SCRATCH/benchmarks/osu/intel/libexec/osu-micro-benchmarks/mpi"
# Mapa pedido de colectivas: 32 en bloque por socket; NUMA node0 = CPUs 0-55, node1 = 56-111.
MAP64="$(seq -s, 0 31),$(seq -s, 56 87)"
MAPCHECK='echo "$(hostname -s) rank=${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-${SLURM_PROCID:-NA}}} cpus=$(taskset -pc $$ | awk "{print \$NF}")"'

mkdir -p "$CMDLOG_DIR" data/raw/phaseA

# NUMA del HCA e interfaces, un task por nodo (sysfs sin privilegios).
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

# Interfaz tcp común: IPoIB preferente; se declara y queda en el log de cada run.
TCP_IFACE="$(ip -o -4 addr show | awk '$2 ~ /^(ib|ibs)/ {print $2; exit}')"
[ -n "${TCP_IFACE:-}" ] || TCP_IFACE="$(ip -o -4 addr show | awk '$2 != "lo" {print $2; exit}')"
echo "== interfaz tcp fijada: $TCP_IFACE (igual en ambas pilas)"

# Core pt2pt: primer core del dominio NUMA del HCA de 200 Gb/s (salida de nodo_info).
elige_map1() {
  first="$(printf '%s\n' "$1" | grep -a 'rate=200' | head -1 | sed -n 's/.*numa_node=\([0-9-]*\).*/\1/p')"
  ndoms="$(printf '%s\n' "$1" | grep -a 'rate=200' | sed -n 's/.*numa_node=\([0-9-]*\).*/\1/p' | sort -u | wc -l | tr -d ' ')"
  case "$first" in
    0) echo 0 ;;
    1) echo 56 ;;
    *) echo "AVISO-NUMA:no-determinable" ;;
  esac
  [ "$ndoms" != "1" ] && echo "AVISO-NUMA:dominios-no-univocos=$ndoms" >&2
  return 0
}

# Lanzador por pila con el MISMO mapa explícito para ambas (§Binding AGENTS.md):
#   gcc:   mpirun (Open MPI): pt2pt --map-by ppr:1:node; colectivas ppr:32:socket; --bind-to core
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

humo_par() { # pila trans ntasks ppn map osu_dir test_bin [args del test]
  local pila="$1" trans="$2" ntasks="$3" ppn="$4" map="$5" osudir="$6" tbin="$7"
  shift 7
  case "$pila" in
    gcc)   module purge 2>/dev/null || true; module load openmpi_gcc/5.0.5 ucx/1.9.0
           export OMPI_MCA_pml=ucx UCX_TLS="${trans},sm,self" UCX_LOG_LEVEL=info
           unset I_MPI_FABRICS FI_PROVIDER FI_TCP_IFACE I_MPI_DEBUG I_MPI_PMI_LIBRARY I_MPI_PIN_PROCESSOR_LIST
           [ "$trans" = tcp ] && export UCX_NET_DEVICES="$TCP_IFACE" ;;
    intel) module purge 2>/dev/null || true; module load intel/2025.3.2
           export I_MPI_FABRICS=ofi FI_PROVIDER="$trans" I_MPI_DEBUG=5
           unset OMPI_MCA_pml UCX_TLS UCX_LOG_LEVEL UCX_NET_DEVICES
           [ "$trans" = tcp ] && export FI_TCP_IFACE="$TCP_IFACE" ;;
  esac
  launch_setup "$pila" "$ntasks" "$ppn"
  echo "### par $pila/$trans"
  echo "--- mapa pedido = $map (equivalente map_cpu); mapa real por rank:"
  "${LAUNCH[@]}" bash -c "$MAPCHECK" || echo "!! mapa-check FALLO $pila/$trans"
  echo "--- prueba OSU: $tbin $*"
  if ! bash "$CMDLOG" "${LAUNCH[@]}" "$osudir/$tbin" "$@"; then
    echo "!! FALLO $pila/$trans"
    if [ "$pila" = gcc ] && [ "$trans" = tcp ] && [ -n "${UCX_NET_DEVICES:-}" ]; then
      echo "== reintento gcc/tcp SIN UCX_NET_DEVICES (interfaz no forzada; el efectivo se observa del log)"
      unset UCX_NET_DEVICES
      bash "$CMDLOG" "${LAUNCH[@]}" "$osudir/$tbin" "$@" || echo "!! FALLO gcc/tcp tambien sin UCX_NET_DEVICES"
    fi
  fi
}

case "$PARTE" in
  pt2pt)
    INFO="$(nodo_info)"
    echo "$INFO"
    MAP1="$(elige_map1 "$INFO")"
    case "$MAP1" in 0|56) ;; *) echo "AVISO: MAP1 no determinado ($MAP1); se usa core 0 y se declara"; MAP1=0 ;; esac
    echo "== core pt2pt (primer core del dominio NUMA del HCA): $MAP1"
    for t in rc dc ud tcp; do
      humo_par gcc "$t" 2 1 "$MAP1" "$OSU_GCC/pt2pt" osu_latency
    done
    for t in mlx verbs tcp; do
      humo_par intel "$t" 2 1 "$MAP1" "$OSU_INTEL/pt2pt" osu_latency
    done
    ;;
  colectivas)
    NT=$((SLURM_JOB_NUM_NODES * NPN))
    INFO="$(nodo_info)"
    echo "$INFO"
    for t in rc dc ud tcp; do
      humo_par gcc "$t" "$NT" "$NPN" "$MAP64" "$OSU_GCC/collective" osu_allreduce -m 1024
    done
    for t in mlx verbs tcp; do
      humo_par intel "$t" "$NT" "$NPN" "$MAP64" "$OSU_INTEL/collective" osu_allreduce -m 1024
    done
    # Duración de UNA rep de colectivas con tcp: rango completo 8 B–256 KiB (peor caso).
    echo "== duración de UNA rep de colectivas con tcp (8 B – 256 KiB)"
    humo_par gcc tcp "$NT" "$NPN" "$MAP64" "$OSU_GCC/collective" osu_allreduce -m 262144
    humo_par gcc tcp "$NT" "$NPN" "$MAP64" "$OSU_GCC/collective" osu_alltoall -m 262144
    humo_par intel tcp "$NT" "$NPN" "$MAP64" "$OSU_INTEL/collective" osu_allreduce -m 262144
    humo_par intel tcp "$NT" "$NPN" "$MAP64" "$OSU_INTEL/collective" osu_alltoall -m 262144
    ;;
  *) echo "parte desconocida: $PARTE" >&2; exit 2 ;;
esac
echo "== humo $PARTE terminado (job $SLURM_JOB_ID); registro en $CMDLOG_DIR"
