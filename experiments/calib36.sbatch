#!/usr/bin/env bash
# Mini-calibración de clase NPB para el protocolo ligero de cpu36c (R8.4).
# FT B/C/D a 1 nodo con 32 ranks, ambas pilas, binarios nativos clx (jobs 83301/83312).
# NOTA (DEVIATIONS 2026-10-04): FT exige un número de procesos potencia de 2 — con los
# 36 ranks de la matriz del 2026-09-30, FT aborta ("Expecting a power-of-two number of
# processes", job 83363). Se usan 32 ranks = mayor potencia de 2 <= 36 cores (mapa
# 16 por paquete, los mismos bloques de las colectivas), en la mini-calibración y en
# las celdas FT (N1-N4) del ligero. Una repetición por celda: solo la duración
# (cmdlog duration_ms). Sin nivel 1, como calib.sh duraciones.
# Pre-registro (DEVIATIONS 2026-10-02): la clase del ligero es la MENOR con duración
# >= 30 s a 1 nodo en AMBAS pilas; discrepancias de duración entre pilas se reportan
# pero no cambian la clase.
# El nodo representante del grupo se pasa con --nodelist en el envío (D1):
#   sbatch --nodelist=aac102 experiments/calib36.sbatch   (grupo SMT-off)
#   sbatch --nodelist=acc101 experiments/calib36.sbatch   (grupo SMT-on)
#SBATCH --job-name=cc-calib36
#SBATCH --exclusive
#SBATCH --partition=cpu36c
#SBATCH --nodes=1
#SBATCH --output=data/raw/calib/%x-%j.out
#SBATCH --time=01:30:00

set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/calib/calib36-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="calib36-$SLURM_JOB_ID"
export LEVEL1_MODE="unprivileged"   # R14
W="$TURGALIUM_REPO/instrumentation/cmdlog.sh"
[ -x "$W" ] || { echo "!! falta wrapper $W" >&2; exit 3; }
mkdir -p "$CMDLOG_DIR"

SCRIPT_SHA="$(sha256sum "$(readlink -f "$0")" | awk '{print $1}')"
NPN=32                             # FT exige potencia de 2 (DEVIATIONS 2026-10-04)
echo "== calib36 job=$SLURM_JOB_ID nodo=$(scontrol show hostname "$SLURM_JOB_NODELIST" | tr '\n' ' ')sha256=$SCRIPT_SHA $(date -Is)"

for pila in gcc intel; do
    for clase in B C D; do
        BIN="$TURGALIUM_SCRATCH/benchmarks/npb/$pila/clx/ft.$clase.x"
        [ -x "$BIN" ] || { echo "!! falta binario $BIN" >&2; exit 3; }
    done
done

# Dimensiones de clase (npbparams): la verificación "SUCCESSFUL" de NPB NO distingue
# la clase — los binarios mal relabeled de 83301/83312 (clase B) pasaban y duraban 3 s.
# Si el Size impreso no es el de la clase, el job FALLA (los datos no se usan).
DIMS=( "512x 256x 256" "512x 512x 512" "2048x1024x1024" )
for pila in gcc intel; do
    module purge 2>/dev/null || true
    case "$pila" in
        gcc)   module load openmpi_gcc/5.0.5 ucx/1.9.0
               RUN=(mpirun -np "$NPN" --map-by "ppr:$NPN:node" --bind-to core) ;;
        intel) module load intel/2025.3.2
               RUN=(mpirun -n "$NPN" -ppn "$NPN") ;;   # Hydra: -map-by no soportado
    esac
    i=0
    for clase in B C D; do
        echo "== FT $clase / $pila: 1 nodo x $NPN ranks $(date -Is)"
        RD="$CMDLOG_DIR/ft-$clase-$pila"; mkdir -p "$RD"
        if bash "$W" "${RUN[@]}" "$TURGALIUM_SCRATCH/benchmarks/npb/$pila/clx/ft.$clase.x" \
            > "$RD/run.log" 2>&1; then ec=0; else ec=$?; fi
        if [ "$ec" -ne 0 ]; then
            echo "!! FT $clase/$pila exit=$ec (conservado en $RD/run.log)" >&2; exit 5
        fi
        if ! grep -q "Size.*${DIMS[$i]}" "$RD/run.log"; then
            echo "!! FT $clase/$pila: clase ERRÓNEA (esperaba ${DIMS[$i]}; binario mal compilado)" >&2; exit 5
        fi
        echo "   ok: $(grep -m1 'Size' "$RD/run.log" | tr -s ' ')"
        i=$((i+1))
    done
done
module purge 2>/dev/null || true
echo "== calib36 terminada $(date -Is) — duraciones en $CMDLOG_DIR/commands.jsonl"
