#!/usr/bin/env bash
# Lectura común extraída de experiments/calib36.sbatch.
# Origen SHA256: 8e6ff3d4b2f2ebb8dcfd8d27f8ba3982db6f2b33d2c146aa519101e74f8e86b3
# Se carga desde la raíz; no ejecuta Slurm ni módulos.
set -uo pipefail
: "${PERFIL:?falta PERFIL}"
[ -f "$PERFIL" ] || { printf 'falta perfil: %s\n' "$PERFIL" >&2; return 2; }
unset CLUSTER SSH_ALIAS PARTITION ENV_PREFIX DECLARED_NODES DECLARED_CORES CALIB_NODES
unset GNU_MODULES INTEL_MODULES MARCH PYTHON_DISCOVERY RPN CPU_MAP
unset GNU_TRANSPORTS INTEL_TRANSPORTS NPB_CLASS
unset QOS SBATCH_QOS
# shellcheck source=/dev/null
source "$PERFIL"
QOS="${QOS:-}"
if [ -n "$QOS" ]; then
    export SBATCH_QOS="$QOS"
fi
for key in CLUSTER SSH_ALIAS PARTITION ENV_PREFIX DECLARED_NODES DECLARED_CORES CALIB_NODES \
    MARCH PYTHON_DISCOVERY RPN CPU_MAP GNU_TRANSPORTS INTEL_TRANSPORTS NPB_CLASS; do
    [ -n "${!key:-}" ] || { printf 'falta variable del perfil: %s\n' "$key" >&2; return 2; }
done
declare -p GNU_MODULES INTEL_MODULES >/dev/null 2>&1 || {
    printf 'faltan módulos del perfil\n' >&2; return 2;
}
[ "${#GNU_MODULES[@]}" -gt 0 ] && [ "${#INTEL_MODULES[@]}" -gt 0 ] || return 2
case "$ENV_PREFIX" in XULA|LUSITANIA) ;; *) printf 'prefijo no autorizado\n' >&2; return 2;; esac
[[ "$DECLARED_CORES" =~ ^[1-9][0-9]*$ && "$DECLARED_NODES" =~ ^[1-9][0-9]*$ && "$CALIB_NODES" =~ ^[1-9][0-9]*$ ]] || return 2
[ "$CALIB_NODES" -le "$DECLARED_NODES" ] || { printf 'CALIB_NODES supera DECLARED_NODES\n' >&2; return 2; }
[[ "$PYTHON_DISCOVERY" = /* ]] || { printf 'Python debe ser absoluto\n' >&2; return 2; }
export CLUSTER SSH_ALIAS PARTITION ENV_PREFIX MARCH PYTHON_DISCOVERY
export DECLARED_NODES DECLARED_CORES RPN CPU_MAP GNU_TRANSPORTS INTEL_TRANSPORTS NPB_CLASS
export CALIB_RPN=1
while [ $((CALIB_RPN * 2)) -le "$DECLARED_CORES" ]; do CALIB_RPN=$((CALIB_RPN * 2)); done
if [ "${DRY_RUN:-0}" = 1 ]; then
    export REPO="\$${ENV_PREFIX}_REPO" SCRATCH="\$${ENV_PREFIX}_SCRATCH"
    export WORKDIR="\$${ENV_PREFIX}_WORKDIR" ACCOUNT=""
else
    [ -f "${LOCAL_ENV:-clusters/local.env}" ] || { printf 'falta local.env\n' >&2; return 2; }
    # shellcheck source=/dev/null
    source "${LOCAL_ENV:-clusters/local.env}"
    for key in REPO SCRATCH WORKDIR; do
        name="${ENV_PREFIX}_$key"
        [ -n "${!name:-}" ] || { printf 'falta variable privada: %s\n' "$name" >&2; return 2; }
        printf -v "$key" '%s' "${!name}"
        export "${key?}"
    done
    name="${ENV_PREFIX}_ACCOUNT"; export ACCOUNT="${!name:-}"
    export PATH="${PYTHON_DISCOVERY%/*}:$PATH"
fi
export W="$REPO/instrumentation/cmdlog.sh"

describe_profile() {
    printf 'qos=%s\n' "$QOS"
    printf 'cluster=%s particion=%s rpn=%s mapa=%s calib_rpn=%s\n' \
        "$CLUSTER" "$PARTITION" "$RPN" "$CPU_MAP" "$CALIB_RPN"
    printf 'module purge; module load %s\n' "${GNU_MODULES[*]}" "${INTEL_MODULES[*]}"
}

load_stack() {
    module purge
    unset UCX_TLS UCX_NET_DEVICES UCX_LOG_LEVEL OMPI_MCA_pml
    unset OMPI_MCA_opal_common_ucx_tls OMPI_MCA_opal_common_ucx_devices
    unset I_MPI_FABRICS FI_PROVIDER FI_TCP_IFACE FI_LOG_LEVEL I_MPI_DEBUG
    unset I_MPI_PIN I_MPI_PIN_PROCESSOR_LIST I_MPI_PIN_DOMAIN
    unset GOMP_CPU_AFFINITY KMP_AFFINITY OMP_PROC_BIND OMP_PLACES
    case "$1" in
        gnu) module load "${GNU_MODULES[@]}" ;;
        intel) module load "${INTEL_MODULES[@]}" ;;
        *) return 2 ;;
    esac
}

init_job() {
    [ -f "$W" ] || { printf 'falta cmdlog\n' >&2; return 3; }
    : "${SLURM_JOB_ID:?solo ejecutar dentro de una asignación}"
    export CMDLOG_DIR="$SCRATCH/cc/raw/$CLUSTER/fase1/$1-$SLURM_JOB_ID"
    export CMDLOG_RUN_ID="$1-$SLURM_JOB_ID" LEVEL1_MODE=unprivileged
    mkdir -p "$CMDLOG_DIR"
}
