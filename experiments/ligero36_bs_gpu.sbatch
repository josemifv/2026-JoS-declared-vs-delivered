#!/usr/bin/env bash
# Ligero GPU por partición (DEVIATIONS 2026-10-04, [O] y [P]): BabelStream en TODAS
# las GPU de un nodo, UNA TRAS OTRA (no simultáneas). Un job de 1 nodo por nodo:
#   sbatch --partition=volta --gres=gpu:4 --nodelist=aap01 --time=00:20:00 \
#          experiments/ligero36_bs_gpu.sbatch sm70        (humo primero; el resto
#                                                          tras ver la salida)
#   aap[01-04]: --gres=gpu:4 | acp[01-04]: --gres=gpu:2 | b9p[17-18]: --gres=gpu:4
#   (los de h100 con --dependency=afterok:83389, compilación sm_90)
# Parámetros a priori (DEVIATIONS 2026-10-04): doble precisión, 5 kernels
# (copy/mul/add/triad/dot), --arraysize 2^28 (2 GiB por vector), --mibibytes,
# num_times interno por defecto (100). Reps: 1 calentamiento + 10 efectivas POR GPU
# (ligero 10+1, DEVIATIONS 2026-09-30). Sin binding explícito del proceso anfitrión.
# Contexto por nodo (DEVIATIONS [P]): nvidia-smi -L, topo -m y query-gpu con PCIe
# gen/width current+max, clocks máx y temperatura. Si las GPU visibles no coinciden
# con el gres pedido, se deja escrito y se continúa. Validación por rep: sin
# "Validation failed" y con filas de resultados.
#SBATCH --job-name=cc-lig36-gpu
#SBATCH --exclusive
#SBATCH --gres=gpu:1
#SBATCH --time=00:20:00
#SBATCH --output=data/raw/ligero/%x-%j.out

set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env

if [ "${1:-}" = "__task__" ]; then
    # --- modo tarea: se ejecuta EN el nodo (una tarea que recorre las GPUs) -----
    ARCH="$2"; BASE="$3"
    H="$(hostname -s)"
    export CMDLOG_DIR="$BASE/$H"
    export CMDLOG_RUN_ID="lig-gpu-$SLURM_JOB_ID-$H"
    export LEVEL1_MODE="unprivileged"   # R14
    W="$TURGALIUM_REPO/instrumentation/cmdlog.sh"
    L1="$TURGALIUM_REPO/instrumentation/level1_capture.sh"
    mkdir -p "$CMDLOG_DIR"
    BIN="$TURGALIUM_SCRATCH/benchmarks/babelstream/$ARCH/babelstream"
    [ -x "$BIN" ] || { echo "!! falta $BIN (compilar antes)" >&2; exit 3; }

    # --- contexto GPU del nodo ([P], DEVIATIONS 2026-10-04) --------------------
    nvidia-smi -L > "$CMDLOG_DIR/nvidia-smi-L.txt" 2>&1 || echo "sin nvidia-smi -L"
    nvidia-smi topo -m > "$CMDLOG_DIR/nvidia-smi-topo.txt" 2>&1 || echo "sin topo -m"
    nvidia-smi --query-gpu=index,uuid,pci.bus_id,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max,clocks.max.sm,clocks.max.mem,temperature.gpu \
        --format=csv > "$CMDLOG_DIR/nvidia-smi-gpus.csv" 2>&1 || echo "sin query-gpu"
    PEDIDAS="${SLURM_GPUS_ON_NODE:-${SLURM_JOB_GPUS:-?}}"
    VISIBLES="$(tail -n +2 "$CMDLOG_DIR/nvidia-smi-gpus.csv" 2>/dev/null | grep -c . || true)"
    if [ "${VISIBLES:-0}" != "$PEDIDAS" ]; then
        echo "!! AVISO: GPU visibles ($VISIBLES) != gres pedido ($PEDIDAS) — se continúa, queda escrito" | tee "$CMDLOG_DIR/GRES-MISMATCH.txt"
    fi
    cat "$CMDLOG_DIR/nvidia-smi-L.txt"
    echo "host=$H cpus_proceso=$(taskset -pc $$ | awk '{print $NF}') cuda_visible=${CUDA_VISIBLE_DEVICES:-NA} pedidas=$PEDIDAS visibles=${VISIBLES:-0}"

    bash "$L1" start
    bash "$L1" pre
    echo "job,host,gpu_index,gpu_uuid,pci_bus_id,rep,cell,exit_code,verificacion,runlog" > "$CMDLOG_DIR/manifest-$H.csv"
    # --- una GPU cada vez, en el orden de CUDA_VISIBLE_DEVICES -----------------
    for IDX in $(seq 0 $(( ${VISIBLES:-1} - 1 ))); do
        export CUDA_VISIBLE_DEVICES="$IDX"
        LINE="$(sed -n "$(( IDX + 2 ))p" "$CMDLOG_DIR/nvidia-smi-gpus.csv" 2>/dev/null || true)"
        UUID="$(echo "$LINE" | cut -d, -f2 | tr -d ' ' | cut -c1-40)"
        BUS="$(echo "$LINE" | cut -d, -f3 | tr -d ' ')"
        for r in $(seq 1 11); do
            RD="$CMDLOG_DIR/gpu$IDX-rep-$r"; mkdir -p "$RD"
            echo "--- RUN babelstream/$ARCH host=$H gpu=$IDX uuid=${UUID:-NA} bus=${BUS:-NA} rep=$r $(date -Is)"
            if bash "$W" "$BIN" --arraysize 268435456 --mibibytes --device 0 > "$RD/run.log" 2>&1; then ec=0; else ec=$?; fi
            if [ "$ec" -eq 0 ] && ! grep -q "Validation failed" "$RD/run.log" \
               && grep -Eq '^[A-Za-z]+[[:space:]]+[0-9]+\.' "$RD/run.log"; then v=VALIDA; else v=FALLO; fi
            echo "    -> exit=$ec verif=$v"
            echo "$SLURM_JOB_ID,$H,$IDX,${UUID:-NA},${BUS:-NA},$r,bs-$ARCH,$ec,$v,$RD/run.log" >> "$CMDLOG_DIR/manifest-$H.csv"
        done
    done
    unset CUDA_VISIBLE_DEVICES
    bash "$L1" post
    bash "$L1" stop
    echo "== host $H terminado: $CMDLOG_DIR/manifest-$H.csv"
    exit 0
fi

# --- modo job: lanza UNA tarea en el nodo asignado (job de 1 nodo) ------------
ARCH="${1:?uso: ligero36_bs_gpu.sbatch <sm70|sm90>}"
case "$ARCH" in sm70|sm90) ;; *) echo "!! arquitectura desconocida: $ARCH" >&2; exit 2 ;; esac
SCRIPT_SHA="$(sha256sum "$(readlink -f "$0")" | awk '{print $1}')"
BIN="$TURGALIUM_SCRATCH/benchmarks/babelstream/$ARCH/babelstream"
[ -x "$BIN" ] || { echo "!! falta $BIN (compilar con compile_babelstream.sbatch)" >&2; exit 3; }
module purge 2>/dev/null || true
module load cuda/12.9.1

BASE="$TURGALIUM_SCRATCH/cc/raw/ligero/bs-$SLURM_JOB_ID"
mkdir -p "$BASE"
echo "== ligero GPU job=$SLURM_JOB_ID arch=$ARCH nodo=$(hostname -s) gres=${SLURM_GPUS_ON_NODE:-?} sha256=$SCRIPT_SHA $(date -Is)"
srun --ntasks=1 --ntasks-per-node=1 \
     bash "$(readlink -f "$0")" __task__ "$ARCH" "$BASE"
echo "== ligero GPU $ARCH terminado (job $SLURM_JOB_ID) $(date -Is); manifiesto en $BASE/$(hostname -s)/"
