#!/usr/bin/env bash
# Humo gcc/tcp (hipótesis de lista blanca del pml ucx de Open MPI).
# Por defecto, pml_ucx_tls = "rc_verbs,ud_verbs,rc_mlx5,dc_mlx5,ud_mlx5,cuda_ipc,
# rocm_ipc" (sin tcp) y pml_ucx_devices = "mlx*" (sinónimos de
# opal_common_ucx_tls / opal_common_ucx_devices): con UCX_TLS=tcp,sm,self sobre
# ib0, el componente pml_ucx se rechaza a sí mismo y el pml framework queda vacío
# ("No components were able to be opened in the pml framework"). Este humo repite
# el par con ambos parámetros en "any". NO ejecuta rondas de la fase A.
#
# Uso (desde la raíz del checkout del repo en el clúster):
#   sbatch --nodes=2 --exclude=b9p02,b9p12 --time=00:15:00 experiments/humo_gcc_tcp.sh pt2pt
#   sbatch --nodes=8 --exclude=b9p02,b9p12 --time=00:15:00 experiments/humo_gcc_tcp.sh colectivas
#SBATCH --job-name=cc-humoT
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --time=00:15:00
#SBATCH --output=data/raw/phaseA/humo-gcc-tcp-%x-%j.out

set -uo pipefail
source clusters/local.env
PARTE="${1:?parte: pt2pt|colectivas}"
NPN=64
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/phaseA/humo-gcctcp-$PARTE-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="humoT-$PARTE-$SLURM_JOB_ID"
CMDLOG="instrumentation/cmdlog.sh"
OSU_GCC="$TURGALIUM_SCRATCH/benchmarks/osu/gcc/libexec/osu-micro-benchmarks/mpi"
MAP64="$(seq -s, 0 31),$(seq -s, 56 87)"
MAPCHECK='echo "$(hostname -s) rank=${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-${SLURM_PROCID:-NA}}} cpus=$(taskset -pc $$ | awk "{print \$NF}")"'

mkdir -p "$CMDLOG_DIR" data/raw/phaseA

module purge 2>/dev/null || true
module load openmpi_gcc/5.0.5 ucx/1.9.0
# Pila de lanzamiento idéntica al resto de la fase A (mapa explícito, §Binding):
export OMPI_MCA_pml=ucx
# Hipótesis bajo prueba: lista blanca por defecto del pml ucx fuera de servicio.
export OMPI_MCA_opal_common_ucx_tls=any
export OMPI_MCA_opal_common_ucx_devices=any
# Transporte pedido del par (igual que en los humos y en la fase A):
export UCX_TLS=tcp,sm,self
export UCX_NET_DEVICES=ib0
export UCX_LOG_LEVEL=info

case "$PARTE" in
  pt2pt)
    echo "== pt2pt: b9p cualesquiera SMT-off; 1 rank/nodo en core 0 (dominio NUMA del HCA)"
    echo "--- mapa pedido = 0 (equivalente map_cpu); mapa real por rank:"
    mpirun -np 2 --map-by ppr:1:node --bind-to core bash -c "$MAPCHECK"
    echo "--- osu_latency (barrido completo; efectivo por UCX_LOG_LEVEL=info)"
    bash "$CMDLOG" mpirun -np 2 --map-by ppr:1:node --bind-to core \
      "$OSU_GCC/pt2pt/osu_latency"
    ;;
  colectivas)
    NT=$((SLURM_JOB_NUM_NODES * NPN))
    echo "== colectivas: $SLURM_JOB_NUM_NODES nodos x $NPN ranks"
    echo "--- mapa pedido = map_cpu:$MAP64 ; mapa real por rank:"
    mpirun -np "$NT" --map-by ppr:32:package --bind-to core bash -c "$MAPCHECK"
    echo "--- osu_allreduce -m 1024 (usable-check)"
    bash "$CMDLOG" mpirun -np "$NT" --map-by ppr:32:package --bind-to core \
      "$OSU_GCC/collective/osu_allreduce" -m 1024
    echo "--- duración de UNA rep con tcp: osu_allreduce -m 262144"
    bash "$CMDLOG" mpirun -np "$NT" --map-by ppr:32:package --bind-to core \
      "$OSU_GCC/collective/osu_allreduce" -m 262144
    echo "--- duración de UNA rep con tcp: osu_alltoall -m 262144 (la pedida)"
    bash "$CMDLOG" mpirun -np "$NT" --map-by ppr:32:package --bind-to core \
      "$OSU_GCC/collective/osu_alltoall" -m 262144
    ;;
  *) echo "parte desconocida: $PARTE" >&2; exit 2 ;;
esac
echo "== humo gcc/tcp $PARTE terminado (job $SLURM_JOB_ID); registro en $CMDLOG_DIR"
