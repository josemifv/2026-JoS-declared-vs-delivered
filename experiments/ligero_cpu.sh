#!/usr/bin/env bash
# OBSOLETO, NO USAR: sustituido por experiments/ligero36_osu.sbatch y experiments/ligero36_ft.sbatch (2026-10-04)
# Protocolo ligero CPU (cpu36c hoy; Xula/Lusitania después, scripts de discovery/ sin modificar).
# Reglas: R8 (clase por partición), R9 (kernel: mayor dispersión entre transportes en cpu112c).
# 11 repeticiones por celda (10 efectivas; decisión 2026-09-30, DEVIATIONS).
# Uso: sbatch ligero_cpu.sh <cluster: turgalium|xula|lusitania> <stack> <transporte> <prueba: osu|stream|npb>
#   Las variables del clúster se leen de clusters/local.env con el prefijo en mayúsculas
#   (p. ej. XULA_SCRATCH). El tamaño máximo de job entre subparticiones sigue DEVIATIONS
#   (entrada del 2026-09-25).
# PLACEHOLDERS: <<<PARTITION>>> <<<NODELIST>>> <<<BINDING_MAP>>>
# Mapa de binding derivado para cpu36c (salidas reales de lscpu del descubrimiento,
# DISCOVERY.md 3.1): 36 ranks, un rank por core, 18 por dominio NUMA, bloques
# consecutivos. Idéntico para los dos tipos de nodo: aac (SMT off, NUMA0 0-17 /
# NUMA1 18-35) y acc (SMT on, hermano 0: NUMA0 0-17,36-53 / NUMA1 18-35,54-71):
#   <<<BINDING_MAP>>> = map_cpu:0,1,2,...,35  (ranks 0-17 -> CPUs 0-17, ranks 18-35 -> 18-35)
# Nota D1: en acc Slurm declara 36 CPUs pero el nodo tiene 72 en línea; el mapa
# pedido vs real se registra por run (R10).
#SBATCH --job-name=cc-ligero
#SBATCH --exclusive
#SBATCH --partition=<<<PARTITION>>>
#SBATCH --output=data/raw/ligero/%x-%j.out
#SBATCH --time=02:00:00

set -euo pipefail
source clusters/local.env

CLUSTER="${1:?uso: ligero_cpu.sh <cluster> <stack> <transporte> <prueba>}"
STACK="$2"; TRANSPORT="$3"; PRUEBA="$4"
PREFIX="${CLUSTER^^}"                      # TURGALIUM | XULA | LUSITANIA
SCRATCH_VAR="${PREFIX}_SCRATCH"
SCRATCH="${!SCRATCH_VAR:?definir ${SCRATCH_VAR} en local.env}"

export CMDLOG_DIR="$SCRATCH/cc/raw/ligero/$SLURM_JOB_ID"
export CMDLOG_RUN_ID="lig-$CLUSTER-$SLURM_JOB_ID"
export LEVEL1_MODE="${LEVEL1_MODE:?fijar LEVEL1_MODE (R14): privileged|unprivileged|auto}"

REPO="$TURGALIUM_REPO"                          # wrapper y captura de nivel 1
W="$REPO/instrumentation/cmdlog.sh"
L1="$REPO/instrumentation/level1_capture.sh"
STREAM_BIN="$SCRATCH/src/stream/stream_c"       # binario precompilado (R14.4)
OSU_DIR="$SCRATCH/benchmarks/osu/$STACK/libexec/osu-micro-benchmarks/mpi/pt2pt"  # build POR PILA (DEVIATIONS 2026-10-02)
NPN="${SLURM_CPUS_ON_NODE:?sin SLURM_CPUS_ON_NODE}"   # un rank/hilo por core físico
REP=11                            # 10 efectivas + 1 de calentamiento (R1; DEVIATIONS 2026-09-30)

# Módulos del stack para este clúster: MODULES_<STACK> en local.env (compartido entre
# clústeres solo si coincide); si el conjunto está vacío o no existe (pila no
# disponible en el clúster), el job se detiene y se declara: las celdas de esa
# pila no se ejecutan.
MODULES_VAR="MODULES_${STACK^^}"
MODS="${!MODULES_VAR:-}"
if [ -z "$MODS" ]; then
    echo "pila sin módulos: $MODULES_VAR vacío en local.env — celdas de esta pila omitidas y declaradas" >&2
    exit 3
fi
module load $MODS

# Transporte no por defecto: UCX_TRANSPORTS en Open MPI/UCX, FI_PROVIDER en
# Intel MPI/libfabric. "default" = lo que el stack traiga por defecto.
if [ "$TRANSPORT" != "default" ]; then
    export UCX_TRANSPORTS="$TRANSPORT" FI_PROVIDER="$TRANSPORT"
fi

$L1 start
$L1 pre
case "$PRUEBA" in
  stream)
    # Triad a 1 nodo: el mapa explícito (ranks/hilos 0-17 -> NUMA0, 18-35 -> NUMA1,
    # un core físico por hilo, hermanos SMT evitados) se expresa aquí con OMP:
    # PLACES=cores + PROC_BIND=close recorre los cores en orden del sistema,
    # que es el mismo orden del mapa. El mapa pedido y el real quedan en el
    # contexto de nivel 1 de cada rep (R10).
    export OMP_NUM_THREADS="$NPN" OMP_PLACES=cores OMP_PROC_BIND=close
    for i in $(seq 1 "$REP"); do
        echo "== rep $i =="
        bash "$W" "$STREAM_BIN"
    done
    ;;
  lat|bw)
    # OSU pt2pt a 2 nodos, 1 rank por nodo, lanzador de Open MPI (no hay
    # srun --mpi=pmix en este Slurm). El análisis toma 8 B (lat) o 4 MiB (bw)
    # y descarta la rep de calentamiento.
    BIN="$OSU_DIR/osu_latency"
    [ "$PRUEBA" = bw ] && BIN="$OSU_DIR/osu_bw"
    export PATH="$OSU_DIR:$PATH"
    command -v "$(basename "$BIN")" >/dev/null || { echo "OSU no disponible: $BIN" >&2; exit 1; }
    for i in $(seq 1 "$REP"); do
        echo "== rep $i =="
        case "$STACK" in
            gcc)   mpirun -np 2 --map-by ppr:1:node bash "$W" "$BIN" ;;   # Open MPI: lee los nodos de Slurm
            oneapi|intel) mpirun -n 2 -ppn 1 bash "$W" "$BIN" ;;          # Hydra: -map-by no soportado
        esac
    done
    ;;
  npb)
    # Requiere kernel (R9, fin de fase B) y clase (R8.4, mini-calibración):
    # no se implementa hasta que ambas estén fijadas.
    echo "npb pendiente: kernel R9 y clase R8.4 no fijados todavía" >&2
    exit 2
    ;;
  *) echo "prueba desconocida: $PRUEBA (stream|lat|bw|npb)" >&2; exit 2 ;;
esac
$L1 post
$L1 stop
