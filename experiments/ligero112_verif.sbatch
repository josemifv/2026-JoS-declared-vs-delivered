#!/usr/bin/env bash
# Verificación funcional (0b, DEVIATIONS 2026-10-03) del protocolo ligero
# INDEPENDIENTE de cpu112c (E-f repetido, DEVIATIONS 2026-10-06 D18).
# Por cada combinación pila+transporte que va a medirse, comprueba en ejecución:
#   (1) el transporte efectivamente cargado (lanes UCX inter-node en gcc; proveedor
#       libfabric en intel), (2) el mapa de afinidad real frente al pedido (R10) para
#       el mapa de 64 ranks/nodo (0-31,56-87), (3) las librerías que el proceso MPI
#       carga (ldd del binario + versiones impresas en el probe).
# Además registra el emplazamiento pt2pt de cada nodo (primer core del NUMA local al
# HCA, sysfs sin privilegios) con el helper ligero36_pin.sh (mecanismo común; su
# nombre hace referencia a cpu36c pero es genérico: lee el sysfs del nodo).
# Veredicto OK = probe exit 0 Y transporte observado = solicitado. Una discrepancia
# declarado/real NO consume rondas sin consulta a la persona (DEVIATIONS 2026-10-03):
# el veredicto se escribe en $TURGALIUM_SCRATCH/cc/config/ligero112-verif.csv y los
# jobs OSU del ligero (ligero112_osu.sbatch) saltan las combinaciones sin veredicto OK.
# Asignación: 2 nodos fijos SMT-off del grupo de la fase A (el par pt2pt de L2b).
# Uso:
#   sbatch --nodelist=b9p03,b9p04 experiments/ligero112_verif.sbatch               (los 7 combos; CSV nuevo)
#   sbatch --nodelist=b9p03,b9p04 experiments/ligero112_verif.sbatch intel "verbs;ofi_rxm"  (solo ese combo; AÑADE al CSV)
# El transporte intel/verbs se pasa como en la fase A: FI_PROVIDER="verbs;ofi_rxm"
# (el proveedor elegido por libfabric se registra completo, p. ej. "verbs;ofi_rxm").
#SBATCH --job-name=cc-verif112
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --nodes=2
#SBATCH --output=data/raw/ligero112/%x-%j.out
#SBATCH --time=00:30:00

set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}" || exit 1
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env

SCRIPT_SHA="$(sha256sum "$(readlink -f "$0")" | awk '{print $1}')"
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/ligero112/verif112-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="verif112-$SLURM_JOB_ID"
export LEVEL1_MODE="unprivileged"   # R14
mkdir -p "$CMDLOG_DIR" "$TURGALIUM_SCRATCH/cc/config" data/raw/ligero112

OSU_GCC="$TURGALIUM_SCRATCH/benchmarks/osu/gcc/spr/libexec/osu-micro-benchmarks/mpi/pt2pt"
OSU_INTEL="$TURGALIUM_SCRATCH/benchmarks/osu/intel/spr/libexec/osu-micro-benchmarks/mpi/pt2pt"
PIN_SH="$TURGALIUM_REPO/experiments/helpers/ligero36_pin.sh"
for d in "$OSU_GCC/osu_latency" "$OSU_INTEL/osu_latency"; do
    [ -x "$d" ] || { echo "!! falta $d (OSU spr de fase A)" >&2; exit 3; }
done
[ -f "$PIN_SH" ] || { echo "!! falta $PIN_SH" >&2; exit 3; }

# v2 (Prompt C 4.5): interfaz TCP con la MISMA fuente que fase_a.sh:125-127
TCP_IFACE="$(ip -o -4 addr show | awk '$2 ~ /^(ib|ibs)/ {print $2; exit}')"
[ -n "${TCP_IFACE:-}" ] || TCP_IFACE="$(ip -o -4 addr show | awk '$2 != "lo" {print $2; exit}')"
echo "== interfaz tcp fijada: $TCP_IFACE (igual en ambas pilas; fase_a.sh:125-127)"

echo "== verif112 job=$SLURM_JOB_ID sha256=$SCRIPT_SHA nodos asignados:"
srun --ntasks="$SLURM_JOB_NUM_NODES" --ntasks-per-node=1 hostname -s | sort | tr '\n' ' '; echo

# Emplazamiento pt2pt por nodo (R10; DEVIATIONS 2026-10-03/2026-10-04)
srun --ntasks="$SLURM_JOB_NUM_NODES" --ntasks-per-node=1 bash "$PIN_SH" true \
    > "$CMDLOG_DIR/hca-pin.txt" 2>&1 || echo "!! hca-pin con fallos (conservado)"
cat "$CMDLOG_DIR/hca-pin.txt"

# Mapa de afinidad pedido vs real (R10), el usado por colectivas y FT-8n del ligero
# de cpu112c: 64 ranks/nodo en bloques de 32 por paquete (0-31, 56-87).
MAPCHECK='echo "$(hostname -s) rank=${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-${SLURM_PROCID:-NA}}} cpus=$(taskset -pc $$ | awk "{print \$NF}")"'
map_check() { # $1 = pila; $2 = etiqueta; $3 = ranks totales
    local pila="$1" et="$2" nt="$3"
    local rpn=$(( nt / SLURM_JOB_NUM_NODES ))
    case "$pila" in
      gcc)   # T05: la pila gcc NO fija I_MPI_PIN (antes lo exportaba a 0 y se colaba
             # en Intel por herencia del entorno); se limpia explícitamente
             unset I_MPI_PIN I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true
             mpirun -np "$nt" --map-by "ppr:$(( rpn / 2 )):package" --bind-to core bash -c "$MAPCHECK" ;;
      intel) export I_MPI_PIN=1 I_MPI_PIN_PROCESSOR_LIST="0-31,56-87"
             mpirun -n "$nt" -ppn "$rpn" bash -c "$MAPCHECK" ;;
    esac > "$CMDLOG_DIR/mapcheck-$pila-$et.txt" 2>&1 \
      || echo "!! map-check FALLO $pila/$et (conservado)"
    echo "   map-check $pila/$et: $(grep -c 'cpus=' "$CMDLOG_DIR/mapcheck-$pila-$et.txt" || echo 0) ranks"
}

transport_label() { # $1 = pila; $2 = run.log  (|| true: con pipefail, un grep sin
  case "$1" in         # match no debe matar el job — patrón de fase_b)
    gcc)   grep -oE 'inter-node cfg#[0-9]+ tag\([a-z_0-9/]+' "$2" | grep -oE 'tag\(.*' | sort -u | tr '\n' ' ' || true ;;
    intel) grep -m1 -oE 'libfabric provider[:= ]*[a-z_;]+' "$2" | head -1 || true ;;
  esac
}

MANIFEST="$TURGALIUM_SCRATCH/cc/config/ligero112-verif.csv"
if [ $# -ge 1 ]; then
    # Modo combinación única: AÑADE al veredicto existente (no lo trunca)
    case "$1" in gcc|intel) ;; *) echo "!! pila desconocida: $1" >&2; exit 2;; esac
    [ -n "${2:-}" ] || { echo "!! falta el transporte" >&2; exit 2; }
    COMBOS=( "$1 $2" )
    [ -f "$MANIFEST" ] || echo "pila,transporte,probe_exit,transporte_observado,coincide,veredicto" > "$MANIFEST"
else
    # D18: los SIETE pares disponibles (gcc rc/dc/ud/tcp; intel mlx/verbs/tcp)
    COMBOS=( "gcc rc" "gcc dc" "gcc ud" "gcc tcp" "intel mlx" "intel verbs;ofi_rxm" "intel tcp" )
    echo "pila,transporte,probe_exit,transporte_observado,coincide,veredicto" > "$MANIFEST"
fi

N_OK=0
for p in "${COMBOS[@]}"; do
  set -- $p; PILA="$1"; TRANS="$2"
  case "$PILA" in
    gcc)   OSU_DIR="$OSU_GCC";   MODS="openmpi_gcc/5.0.5 ucx/1.9.0" ;;
    intel) OSU_DIR="$OSU_INTEL"; MODS="intel/2025.3.2" ;;
  esac
  module purge 2>/dev/null || true; module load $MODS

  case "$PILA" in
    gcc)   export OMPI_MCA_pml=ucx UCX_LOG_LEVEL=info
           if [ "$TRANS" = tcp ]; then
               export UCX_TLS="tcp,sm,self" OMPI_MCA_opal_common_ucx_tls=any OMPI_MCA_opal_common_ucx_devices=any
               export UCX_NET_DEVICES="$TCP_IFACE"   # v2 (Prompt C 4.5): fase_a.sh:88
           else
               export UCX_TLS="$TRANS,sm,self"
               unset UCX_NET_DEVICES 2>/dev/null || true
           fi
           unset I_MPI_FABRICS FI_PROVIDER FI_TCP_IFACE I_MPI_DEBUG I_MPI_PIN I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true
           PROBE=(mpirun -np 2 --map-by ppr:1:node --bind-to none bash "$PIN_SH") ;;
    intel) export I_MPI_FABRICS=ofi FI_PROVIDER="$TRANS" I_MPI_DEBUG=5 I_MPI_PIN=0
           unset OMPI_MCA_pml UCX_TLS UCX_LOG_LEVEL UCX_NET_DEVICES I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true
           if [ "$TRANS" = tcp ]; then export FI_TCP_IFACE="$TCP_IFACE"; else unset FI_TCP_IFACE 2>/dev/null || true; fi   # v2 (Prompt C 4.5): fase_a.sh:96
           PROBE=(mpirun -n 2 -ppn 1 bash "$PIN_SH") ;;
  esac

  RD="$CMDLOG_DIR/probe-$PILA-$TRANS"; mkdir -p "$RD"
  if "${PROBE[@]}" "$OSU_DIR/osu_latency" -m 8192 > "$RD/run.log" 2>&1; then EC=0; else EC=$?; fi
  ldd "$OSU_DIR/osu_latency" | grep -E 'libmpi|libucp|libfabric' > "$RD/libs.txt" 2>&1 || true
  OBS="$(transport_label "$PILA" "$RD/run.log")"
  OBS="${OBS:-sin-observar}"

  if [ "$EC" -ne 0 ] || [ "$OBS" = "sin-observar" ]; then V=FALLO; C=no
  elif echo "$OBS" | grep -q -- "$TRANS"; then V=OK; C=si
  else V=MISMATCH; C=no; fi

  echo "$PILA,$TRANS,$EC,$OBS,$C,$V" >> "$MANIFEST"
  if [ "$V" = OK ]; then N_OK=$((N_OK+1)); fi
  map_check "$PILA" 64 128
done
module purge 2>/dev/null || true

echo "== resultado: $N_OK/${#COMBOS[@]} OK — veredictos en $MANIFEST"
cat "$MANIFEST"
[ "$N_OK" -gt 0 ] || { echo "!! 0 combos OK" >&2; exit 4; }
VALIDADOR="$TURGALIUM_REPO/experiments/lib/valida_job.sh"
if bash "$VALIDADOR" --salida "$CMDLOG_DIR/validacion-$CMDLOG_RUN_ID.txt" "$(dirname "$MANIFEST")"; then
  :
else
  case "$?" in
    1) echo "VEREDICTO: REVISAR" ;;
    *) echo "VALIDADOR-NO-EJECUTADO" ;;
  esac
fi
