#!/usr/bin/env bash
# Origen: experiments/ligero112_verif.sbatch
# SHA256: c72705ae107f3c912d1c295b351e27e13f963cf9a76c02a16ece5f00f9ed72ce
# T29: cambia módulos/rutas y enumeración, no el probe OSU de 8192 ni su pin.
# No se presupone un transporte; fallos y diferencias se conservan.
#SBATCH --job-name=portable-verif
#SBATCH --exclusive
#SBATCH --nodes=2
#SBATCH --time=01:00:00
# T46: cada prueba tiene un límite de 120 s; el agotamiento queda en el manifiesto.
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")/../..}"
source experiments/portable/perfil.sh
if [ "${DRY_RUN:-0}" = 1 ]; then
    describe_profile
    for pila in gnu intel; do
        printf 'pila=%s bin=%s/benchmarks/osu/%s/%s/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_latency ranks=2 rpn=1 mapa=HCA-local\n' \
            "$pila" "$SCRATCH" "$pila" "$PARTITION"
    done
    printf 'enumeracion=ucx_info -d | fi_info; transportes=POR_DETERMINAR\n'
    exit 0
fi
init_job verif
[ "${SLURM_JOB_NUM_NODES:?}" = 2 ] || exit 2
MANIFEST="$CMDLOG_DIR/manifest.csv"
printf 'pila,transporte,probe_exit,transporte_observado,coincide,mapa,bibliotecas,veredicto\n' > "$MANIFEST"
PIN_SH="$REPO/experiments/portable/pin.sh"
TCP_IFACE="$(ip -o -4 addr show | awk '$2 ~ /^(ib|ibs)/ {print $2; exit}')"
[ -n "$TCP_IFACE" ] || TCP_IFACE="$(ip -o -4 addr show | awk '$2 != "lo" {print $2; exit}')"
N_OK=0
for pila in gnu intel; do
    load_stack "$pila"
    MAPCHECK='echo "$(hostname -s) rank=${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-NA}} cpus=$(taskset -pc $$ | awk "{print \$NF}")"'
    case "$pila" in
        gnu) MAPRUN=(mpirun -np "$((2 * CALIB_RPN))" --map-by "ppr:$CALIB_RPN:node" --bind-to core) ;;
        intel) MAPRUN=(mpirun -n "$((2 * CALIB_RPN))" -ppn "$CALIB_RPN") ;;
    esac
    map_ec=0
    bash "$W" "${MAPRUN[@]}" bash -c "$MAPCHECK" > "$CMDLOG_DIR/mapcheck-$pila.txt" 2>&1 || map_ec=$?
    printf '%s mapa_provisional=POR_DETERMINAR rpn=%s map_exit=%s\n' \
        "$pila" "$CALIB_RPN" "$map_ec" >> "$CMDLOG_DIR/mapcheck-status.txt"
    ec=0
    case "$pila" in
        gnu)
            bash "$W" ucx_info -d > "$CMDLOG_DIR/ucx-info.txt" 2>&1 || ec=$?
            awk '/Transport:/ {print $NF}' "$CMDLOG_DIR/ucx-info.txt" | sort -u > "$CMDLOG_DIR/transportes-gnu.txt"
            ;;
        intel)
            bash "$W" fi_info > "$CMDLOG_DIR/fi-info.txt" 2>&1 || ec=$?
            awk '/provider:/ {print $NF}' "$CMDLOG_DIR/fi-info.txt" | sort -u > "$CMDLOG_DIR/transportes-intel.txt"
            ;;
    esac
    printf '%s enumeracion_exit=%s\n' "$pila" "$ec" >> "$CMDLOG_DIR/enumeracion.txt"
    if [ "$ec" -ne 0 ] || [ ! -s "$CMDLOG_DIR/transportes-$pila.txt" ]; then
        printf '%s,enumeracion,%s,sin-observar,no,no,no,FALLO-ENUMERACION\n' "$pila" "$ec" >> "$MANIFEST"
        continue
    fi
    i=0
    while IFS= read -r trans <&3; do
        i=$((i+1)); RD="$CMDLOG_DIR/probe-$pila-$i"; mkdir -p "$RD"
        load_stack "$pila"
        case "$pila" in
            gnu)
                export OMPI_MCA_pml=ucx UCX_LOG_LEVEL=info UCX_TLS="$trans,sm,self"
                if [ "$trans" = tcp ]; then
                    export UCX_NET_DEVICES="$TCP_IFACE"
                    export OMPI_MCA_opal_common_ucx_tls=any OMPI_MCA_opal_common_ucx_devices=any
                fi
                PROBE=(mpirun -np 2 --map-by ppr:1:node --bind-to none bash "$PIN_SH")
                ;;
            intel)
                export I_MPI_FABRICS=ofi FI_PROVIDER="$trans" FI_LOG_LEVEL=info I_MPI_DEBUG=5 I_MPI_PIN=0
                if [ "$trans" = tcp ] || [[ "$trans" = tcp\;* ]]; then export FI_TCP_IFACE="$TCP_IFACE"; fi
                PROBE=(mpirun -n 2 -ppn 1 bash "$PIN_SH")
                ;;
        esac
        BIN="$SCRATCH/benchmarks/osu/$pila/$PARTITION/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_latency"
        export CMDLOG_RUN_ID="probe-$pila-$i-$SLURM_JOB_ID"
EC=0
        if command -v timeout >/dev/null 2>&1; then
timeout --signal=TERM --kill-after=10s 120 bash "$W" "${PROBE[@]}" "$BIN" -m 8192 > "$RD/run.log" 2>&1 || EC=$?
        else
            bash "$W" "${PROBE[@]}" "$BIN" -m 8192 > "$RD/run.log" 2>&1 || EC=$?
        fi
        LIB_EC=0; bash "$W" ldd "$BIN" > "$RD/libs.txt" 2>&1 || LIB_EC=$?
        if [ "$EC" -eq 124 ] || [ "$EC" -eq 137 ]; then
            printf '%s,%s,%s,sin-observar,no,no,%s,TIMEOUT\n' "$pila" "$trans" "$EC" "$LIB_EC" >> "$MANIFEST"
        else
            "$PYTHON_DISCOVERY" "$REPO/experiments/portable/observa.py" \
                "$pila" "$trans" "$EC" "$LIB_EC" "$RD/run.log" "$RD/libs.txt" >> "$MANIFEST"
        fi
        if grep -q "^$pila,$trans,.*[, ]OK$" "$MANIFEST"; then N_OK=$((N_OK+1)); fi
    done 3< "$CMDLOG_DIR/transportes-$pila.txt" < /dev/null
done
module purge
cat "$MANIFEST"
[ "$N_OK" -gt 0 ] || exit 4
