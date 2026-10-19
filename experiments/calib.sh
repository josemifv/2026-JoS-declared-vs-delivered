#!/usr/bin/env bash
# Calibración (etapa 3). Reglas: R8 (clase NPB), R3 (sobrecarga nivel 1), R13 (presupuesto).
# Ejecutar en 2 tandas: (1) duraciones a 2 nodos para fijar clase NPB; (2) a 8 nodos:
# colectivas OSU + celda de referencia de R3 (FT, con y sin instrumentación).
# Uso: sbatch calib.sh <parte: duraciones|referencia> [clase para 'referencia', por defecto D]
# PLACEHOLDERS: <<<PARTITION>>> <<<NODELIST>>>
#   Binarios previos: scratch/benchmarks/npb/{gcc,intel}/ft.{B,C,D}.x y
#   scratch/benchmarks/osu (R14.4; compilación registrada por wrapper).
#   El binding de los runs: --map-by ppr:64:node --bind-to core (equivalente al
#   mapa explícito balanceado por sockets/NUMA; el nivel 1 registra el mapa real, R10).
#SBATCH --job-name=cc-calib
#SBATCH --exclusive
#SBATCH --partition=<<<PARTITION>>>
#SBATCH --nodelist=<<<NODELIST>>>
#SBATCH --nodes=<<<NNODES>>>
#SBATCH --output=data/raw/calib/%x-%j.out
#SBATCH --time=01:00:00

set -euo pipefail
source clusters/local.env          # valores locales; nunca versionar este fichero
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/calib/$SLURM_JOB_ID"
export CMDLOG_RUN_ID="calib-$SLURM_JOB_ID"
export LEVEL1_MODE="unprivileged"  # R14, registrado en clusters/turgalium.md
REPO="$TURGALIUM_REPO"
NPN=64                             # ranks por nodo

# OSU se compila POR PILA (R14.4): un binario enlazado a Open MPI bajo la pila
# intel arranca como singletons (la libmpi de Open MPI no entiende Hydra).
carga_pila() {                     # $1 = gcc|intel: módulos + rutas OSU de la pila
    module purge 2>/dev/null || true
    case "$1" in
        gcc)   module load openmpi_gcc/5.0.5 ucx/1.9.0 ;;
        intel) module load intel/2025.3.2 ;;
    esac
    COLL_DIR="$TURGALIUM_SCRATCH/benchmarks/osu/$1/libexec/osu-micro-benchmarks/mpi/collective"
}

run_mpi() {                        # $1 = pila; $2 = ranks; $3 = ranks/nodo; resto = comando
    local pila="$1" nr="$2" ppn="$3"; shift 3
    case "$pila" in
        gcc)   mpirun -np "$nr" --map-by "ppr:$ppn:node" --bind-to core "$@" ;;
        intel) mpirun -n "$nr" -ppn "$ppn" "$@" ;;   # Hydra: -map-by no soportado
    esac
}

case "${1:-}" in
  duraciones)
    # R8: FT por clase candidata (B, C, D), 2 nodos, 64 ranks/nodo; duración por
    # clase y pila. La memoria total de la clase se deriva del MaxRSS por nodo
    # (sacct), constante respecto del número de ranks (escalamiento fuerte).
    for pila in gcc intel; do
        carga_pila "$pila"
        for clase in B C D; do
            echo "== FT $clase / $pila: 2 nodos x $NPN ranks =="
            run_mpi "$pila" $((2*NPN)) $NPN \
                "$TURGALIUM_SCRATCH/benchmarks/npb/$pila/ft.$clase.x"
        done
    done
    ;;
  referencia)
    # R3 (8 nodos): colectivas OSU (64 KiB, para R2) + celda de referencia FT
    # (clase fijada por R8) con y sin nivel 1, por pila; la diferencia de
    # duración es la sobrecarga. El mismo nivel se aplica a ambas pilas (R3.4).
    CLASS="${2:-D}"
    for pila in gcc intel; do
        carga_pila "$pila"
        echo "== colectivas OSU / $pila: allreduce + alltoall, 8x$NPN, 64 KiB =="
        run_mpi "$pila" $((8*NPN)) $NPN "$COLL_DIR/osu_allreduce" -m 65536
        run_mpi "$pila" $((8*NPN)) $NPN "$COLL_DIR/osu_alltoall" -m 65536
        echo "== R3 / $pila: FT $CLASS a 8 nodos SIN nivel 1 =="
        run_mpi "$pila" $((8*NPN)) $NPN \
            "$TURGALIUM_SCRATCH/benchmarks/npb/$pila/ft.$CLASS.x"
        echo "== R3 / $pila: FT $CLASS a 8 nodos CON nivel 1 =="
        bash "$REPO/instrumentation/level1_capture.sh" start
        bash "$REPO/instrumentation/level1_capture.sh" pre
        run_mpi "$pila" $((8*NPN)) $NPN \
            "$TURGALIUM_SCRATCH/benchmarks/npb/$pila/ft.$CLASS.x"
        bash "$REPO/instrumentation/level1_capture.sh" post
        bash "$REPO/instrumentation/level1_capture.sh" stop
    done
    ;;
  *) echo "parte desconocida: ${1:-} (duraciones|referencia)" >&2; exit 2 ;;
esac
