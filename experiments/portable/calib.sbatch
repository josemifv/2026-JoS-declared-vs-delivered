#!/usr/bin/env bash
# Origen: experiments/calib36.sbatch
# SHA256: 8e6ff3d4b2f2ebb8dcfd8d27f8ba3982db6f2b33d2c146aa519101e74f8e86b3
# T29/R8: FT C/D, una ronda/pila, transporte por defecto.
# T46: nodos leídos de CALIB_NODES del perfil.
# RPN provisional = mayor potencia de 2 <= cores declarados (64/16).
# Solo duraciones: no decide clase, mapa ni transporte del perfil definitivo.
#SBATCH --job-name=portable-calib
#SBATCH --exclusive
#SBATCH --nodes=8
#SBATCH --time=00:45:00
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")/../..}"
source experiments/portable/perfil.sh
CALIB_NODES="${CALIB_NODES:?falta CALIB_NODES}"
if [ "${DRY_RUN:-0}" = 1 ]; then
    describe_profile
    for pila in gnu intel; do
        for clase in C D; do
            printf 'pila=%s bin=%s/benchmarks/npb/%s/%s/ft.%s.x nodos=%s rpn=%s ranks=%s mapa=POR_DETERMINAR transporte=default ronda=1\n' \
                "$pila" "$SCRATCH" "$pila" "$PARTITION" "$clase" "$CALIB_NODES" "$CALIB_RPN" "$((CALIB_NODES * CALIB_RPN))"
        done
    done
    exit 0
fi
init_job calib
[ "${SLURM_JOB_NUM_NODES:?}" = "$CALIB_NODES" ] || exit 2
MANIFEST="$CMDLOG_DIR/manifest.csv"
printf 'pila,kernel,clase,nodes,rpn,ronda,transporte,exit_code,verificacion\n' > "$MANIFEST"
FAILED=0
for pila in gnu intel; do
    load_stack "$pila"
    case "$pila" in
        gnu) RUN=(mpirun -np "$((CALIB_NODES * CALIB_RPN))" --map-by "ppr:$CALIB_RPN:node" --bind-to core) ;;
        intel) RUN=(mpirun -n "$((CALIB_NODES * CALIB_RPN))" -ppn "$CALIB_RPN") ;;
    esac
    for clase in C D; do
        RD="$CMDLOG_DIR/ft-$clase-$pila"; mkdir -p "$RD"
        BIN="$SCRATCH/benchmarks/npb/$pila/$PARTITION/ft.$clase.x"
        export CMDLOG_RUN_ID="ft-$clase-$pila-$SLURM_JOB_ID"
        ec=0; bash "$W" "${RUN[@]}" "$BIN" > "$RD/run.log" 2>&1 || ec=$?
        case "$clase" in C) dims='512 *x *512 *x *512';; D) dims='2048 *x *1024 *x *1024';; esac
        v=SUCCESSFUL
        if [ "$ec" -ne 0 ] || ! grep -qE "Size *= *$dims" "$RD/run.log" || \
            ! grep -qE 'Verification *= *SUCCESSFUL' "$RD/run.log"; then
            v=FALLO; FAILED=1
        fi
        printf '%s,ft,%s,%s,%s,1,default,%s,%s\n' "$pila" "$clase" "$CALIB_NODES" "$CALIB_RPN" "$ec" "$v" >> "$MANIFEST"
    done
done
module purge
cat "$MANIFEST"
exit "$FAILED"
