#!/usr/bin/env bash
# Origen del envío/dependencias: launch/20261009-L10-b9p07.sh
# SHA256: 52960dd0df145755eb0b0a79d64a15bd2a3b59a3333264f05c2d170059d9d15d
# T29: ejecutar solo desde L11a/L12a aprobados; DRY_RUN no ejecuta Slurm.
set -euo pipefail
source experiments/portable/perfil.sh
RAW="$SCRATCH/cc/raw/$CLUSTER/fase1"
ACCOUNT_ARGS=(); DISCOVERY_ACCOUNT=()
if [ -n "$ACCOUNT" ]; then
    ACCOUNT_ARGS=("--account=$ACCOUNT")
    DISCOVERY_ACCOUNT=(--account "$ACCOUNT")
fi
DISCOVERY_ARGS=(--cluster "$CLUSTER" --partition "$PARTITION" --repo "$REPO"
    --data-dir "$RAW/discovery" --jobs-dir "$RAW/discovery/jobs" --wrapper "$W"
    --python "$PYTHON_DISCOVERY" ${DISCOVERY_ACCOUNT[@]+"${DISCOVERY_ACCOUNT[@]}"} --submit)
SBATCH_ARGS=(--parsable --exclusive "--partition=$PARTITION" "--chdir=$REPO"
    "--export=ALL,PERFIL=$PERFIL" ${ACCOUNT_ARGS[@]+"${ACCOUNT_ARGS[@]}"})
submit() {
    if [ "${DRY_RUN:-0}" = 1 ]; then
        printf 'sbatch '; printf '%q ' "${SBATCH_ARGS[@]}" "$@"; printf '\n'
    else
        sbatch "${SBATCH_ARGS[@]}" "$@"
    fi
}
if [ "${DRY_RUN:-0}" = 1 ]; then
    describe_profile
    if [ "${SIN_DESCUBRIMIENTO:-0}" != 1 ]; then
        printf 'bash discovery/run_discovery.sh '; printf '%q ' "${DISCOVERY_ARGS[@]}"; printf '\n'
    fi
else
    : "${SLURM_SUBMIT_DIR:=$REPO}"
    export SLURM_SUBMIT_DIR
    [ -x "$PYTHON_DISCOVERY" ] || { printf 'falta Python verificado\n' >&2; exit 3; }
    "$PYTHON_DISCOVERY" -c 'import sys; assert sys.version_info >= (3, 7)'
    [ -f .deploy-commit ] || { printf 'falta .deploy-commit\n' >&2; exit 3; }
    printf 'commit desplegado: '; cat .deploy-commit
    mkdir -p "$RAW"
    # El límite presupuestado corresponde al número declarado de nodos.
    # Si cambió, no reducir el descubrimiento ni ampliar presupuesto sin orden.
    nodes="$(CMDLOG_DIR="$RAW" CMDLOG_RUN_ID=phase1-inventory bash "$W" sinfo -h -N -o '%N' -p "$PARTITION" | sort -u)"
    count="$(printf '%s\n' "$nodes" | awk 'NF {n++} END {print n+0}')"
    [ "$count" = "$DECLARED_NODES" ] || { printf 'cambió el número de nodos\n' >&2; exit 3; }
    if [ "${SIN_DESCUBRIMIENTO:-0}" != 1 ]; then
        bash "$REPO/discovery/run_discovery.sh" "${DISCOVERY_ARGS[@]}" > "$RAW/discovery-submit.log" 2>&1
        cat "$RAW/discovery-submit.log"
        submitted="$(awk '/^enviado .* -> job [0-9]+/ {n++} END {print n+0}' "$RAW/discovery-submit.log")"
        [ "$submitted" = "$DECLARED_NODES" ] || { printf 'descubrimiento incompleto: detener\n' >&2; exit 3; }
    fi
fi
if [ "${SIN_COMPILACION:-0}" = 1 ]; then
    COMPILA=""
elif [ "${DRY_RUN:-0}" = 1 ]; then
    submit --nodes=1 --ntasks=1 --time=01:00:00 "--output=$RAW/compila-%j.out" experiments/portable/compila.sbatch
    COMPILA=COMPILA_JOB_ID
else
    COMPILA="$(submit --nodes=1 --ntasks=1 --time=01:00:00 "--output=$RAW/compila-%j.out" experiments/portable/compila.sbatch)"
    COMPILA="${COMPILA%%;*}"
    [[ "$COMPILA" =~ ^[0-9]+$ ]] || { printf 'job ID no válido\n' >&2; exit 3; }
    printf 'compila job=%s\n' "$COMPILA"
fi
VERIFY_DEP=()
[ -n "$COMPILA" ] && VERIFY_DEP=("--dependency=afterok:$COMPILA")
submit --nodes=2 "--ntasks=$((2 * CALIB_RPN))" "--ntasks-per-node=$CALIB_RPN" --time=01:00:00 ${VERIFY_DEP[@]+"${VERIFY_DEP[@]}"} "--output=$RAW/verif-%j.out" experiments/portable/verif.sbatch
submit --nodes="$CALIB_NODES" "--ntasks=$((CALIB_NODES * CALIB_RPN))" "--ntasks-per-node=$CALIB_RPN" --time=00:45:00 ${VERIFY_DEP[@]+"${VERIFY_DEP[@]}"} "--output=$RAW/calib-%j.out" experiments/portable/calib.sbatch
