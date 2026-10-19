#!/usr/bin/env bash
# Mini-calibración de clase NPB para el protocolo ligero (R8.4, por partición).
# FT B/C/D a 1 nodo con los ranks del nodo completo (36 en cpu36c), ambas pilas,
# binarios nativos clx ya compilados en la etapa 3 (R14.4). Una repetición por
# celda: solo se necesita la duración. Clase de la partición = la menor con
# duración >= 30 s a 1 nodo que quepa en memoria (R8.1).
#
# Uso: rellenar <<<PARTITION>>> y <<<NODELIST>>> con el nodo representante de
# UN grupo de ejecución (propuesta D1 del informe de matriz: aac102 | acc101) y
# lanzar un job por grupo. Sin nivel 1 (como calib.sh duraciones): la sobrecarga
# de la partición se mide aparte.
#SBATCH --job-name=cc-calib36
#SBATCH --exclusive
#SBATCH --partition=<<<PARTITION>>>
#SBATCH --nodelist=<<<NODELIST>>>
#SBATCH --nodes=1
#SBATCH --output=data/raw/calib/%x-%j.out
#SBATCH --time=01:30:00

set -euo pipefail
source clusters/local.env          # valores locales; nunca versionar este fichero
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/calib/$SLURM_JOB_ID"
export CMDLOG_RUN_ID="calib36-$SLURM_JOB_ID"
export LEVEL1_MODE="unprivileged"  # R14, registrado en clusters/turgalium.md
W="$TURGALIUM_REPO/instrumentation/cmdlog.sh"
NPN=36                             # ranks a 1 nodo: un rank por core físico

for pila in gcc intel; do
    module purge 2>/dev/null || true
    case "$pila" in
        gcc)   module load openmpi_gcc/5.0.5 ucx/1.9.0 ;;
        intel) module load intel/2025.3.2 ;;
    esac
    for clase in B C D; do
        echo "== FT $clase / $pila: 1 nodo x $NPN ranks =="
        bash "$W" mpirun -np "$NPN" --bind-to core \
            "$TURGALIUM_SCRATCH/benchmarks/npb/$pila/clx/ft.$clase.x"
    done
done
module purge 2>/dev/null || true
