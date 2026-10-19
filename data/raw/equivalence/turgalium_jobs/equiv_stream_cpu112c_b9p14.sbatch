#!/usr/bin/env bash
# Prueba de equivalencia de grupos de ejecución (DEVIATIONS 2026-09-26).
# Modo usuario: --exclusive, binding por defecto de Slurm (sin mapa explícito),
# CPUs = las que declara Slurm para el nodo. Comparación siempre contra el grupo
# de referencia; nunca en cadena. 11 repeticiones (la 1ª es calentamiento, R1).
#
# Generación: los <<<PLACEHOLDERS>>> los rellena el generador de jobs; los
# binarios se compilan una vez (R14.4; registro en scratch/src/cmdlog).
#
#   stream -> 1 nodo por job (uno por nodo del grupo: dispersión interna).
#   lat|bw -> 2 nodos por job (par dentro del grupo; los candidatos de 1 nodo
#             se miden contra un nodo fijo del grupo de referencia).
#SBATCH --job-name=cc-equival
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --nodelist=b9p14
#SBATCH --nodes=1
#SBATCH --output=<scratch>/cc/raw/equivalence/slurm-%x-%j.out
#SBATCH --time=00:10:00

set -euo pipefail

REPO=<home>
SCRATCH=<scratch>
STREAM_BIN=<scratch>/src/stream/stream_c          # binario STREAM precompilado (40M)
OSU_DIR=<scratch>/benchmarks/osu/libexec/osu-micro-benchmarks/mpi/pt2pt                # .../libexec/osu-micro-benchmarks/mpi/pt2pt
NCPUS=112                    # CPUs declaradas por Slurm (cpu112c: 112; cpu36c: 36)

export CMDLOG_DIR="$SCRATCH/cc/raw/equivalence/$SLURM_JOB_ID"
export CMDLOG_RUN_ID="equiv-$SLURM_JOB_NAME-$SLURM_JOB_ID"
export LEVEL1_MODE=unprivileged      # R14, registrado en clusters/turgalium.md

# Pila GCC + Open MPI, transporte por defecto (decisión 2026-09-26, §3).
module load openmpi_gcc/5.0.5 ucx/1.9.0
export PATH="$OSU_DIR:$PATH"
command -v osu_latency >/dev/null || { echo "osu_latency no disponible" >&2; exit 1; }
command -v osu_bw >/dev/null || { echo "osu_bw no disponible" >&2; exit 1; }

W="$REPO/instrumentation/cmdlog.sh"
L1="$REPO/instrumentation/level1_capture.sh"
PRUEBA=stream                  # stream | lat | bw
REP=11                               # 10 efectivas + 1 de calentamiento (R1)

"$L1" start
"$L1" pre
case "$PRUEBA" in
  stream)
    # Triad; OMP con las CPUs declaradas por Slurm (el efecto usuario del D1).
    export OMP_NUM_THREADS="$NCPUS"
    for i in $(seq 1 "$REP"); do
        echo "== rep $i =="
        bash "$W" "$STREAM_BIN"
    done
    ;;
  lat)
    # Latencia; el análisis toma la fila de 8 B y descarta la rep 1.
    for i in $(seq 1 "$REP"); do
        echo "== rep $i =="
        srun --exclusive --ntasks-per-node=1 --mpi=pmix bash "$W" osu_latency
    done
    ;;
  bw)
    # Ancho de banda; el análisis toma la fila de 4 MiB y descarta la rep 1.
    for i in $(seq 1 "$REP"); do
        echo "== rep $i =="
        srun --exclusive --ntasks-per-node=1 --mpi=pmix bash "$W" osu_bw
    done
    ;;
  *) echo "prueba desconocida: $PRUEBA (stream|lat|bw)" >&2; exit 2 ;;
esac
"$L1" post
"$L1" stop
