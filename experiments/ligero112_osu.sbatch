#!/usr/bin/env bash
# OSU del protocolo ligero INDEPENDIENTE de cpu112c (E-f repetido; DEVIATIONS
# 2026-10-06 D18): OSU propio con TODOS los transportes disponibles y R2 aplicada
# después sobre estos datos. Adaptación de ligero36_osu.sbatch SIN cambiar su
# lógica: 64 ranks/nodo, mapa 0-31,56-87, partición cpu112c.
# Uso:
#   pt2pt (2 nodos, 1 rank/nodo, emplazamiento al NUMA del HCA via ligero36_pin.sh;
#   UN par intra-switch según D18, p. ej. b9p03,b9p04):
#     sbatch --nodelist=b9p03,b9p04 --time=01:30:00 experiments/ligero112_osu.sbatch pt2pt
#   colectivas (8 nodos SMT-off, 64 ranks/nodo = 512, mapa bloques 32/paquete 0-31,56-87);
#   asignaciones de rondas completas <= 3 h (P-5): 1-3, 4-6, 7-9, 10-11:
#     sbatch --nodes=8 --exclude=b9p02,b9p12 --time=02:30:00 experiments/ligero112_osu.sbatch coll 1 3
#     sbatch --nodes=8 --exclude=b9p02,b9p12 --time=02:30:00 experiments/ligero112_osu.sbatch coll 4 6
#     sbatch --nodes=8 --exclude=b9p02,b9p12 --time=02:30:00 experiments/ligero112_osu.sbatch coll 7 9
#     sbatch --nodes=8 --exclude=b9p02,b9p12 --time=02:00:00 experiments/ligero112_osu.sbatch coll 10 11
# Rangos comunes (DEVIATIONS 2026-10-03, los de la fase A): pt2pt -m 8:4194304
# (osu_latency, osu_bw); colectivas -m 262144 (osu_allreduce, osu_alltoall).
# 11 rondas intercaladas (ronda 1 = calentamiento, 10 efectivas; D18).
# Control por asignación (P-2/P-5): osu_allreduce -m 65536 con pila gcc por defecto
# al inicio y al fin de cada asignación.
# Gate: las combinaciones sin verificación funcional OK (ligero112_verif.sbatch) se
# saltan (fila SALTAADA-noverif en el manifiesto) y se declaran; no consumen rondas.
#SBATCH --job-name=cc-lig112-osu
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --output=data/raw/ligero112/%x-%j.out
#SBATCH --time=02:30:00

set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}" || exit 1
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env

# Uso extendido: tras el modo (y rondas opcionales para coll), argumentos restantes =
# pares a medir (pila transporte por parejas); sin ellos, los 7 combos del veredicto.
#   sbatch ... experiments/ligero112_osu.sbatch pt2pt intel "verbs;ofi_rxm"
#   sbatch ... experiments/ligero112_osu.sbatch coll 1 3 intel "verbs;ofi_rxm"
MODE="${1:?uso: ligero112_osu.sbatch <pt2pt|coll> [r_from r_to] [pila transporte ...]}"
shift
if [ "${1:-}" = "" ] || [ "${1:-}" = gcc ] || [ "${1:-}" = intel ]; then
    R_FROM=1; R_TO=11          # sin rondas explícitas: 1..11 (pt2pt siempre)
else
    R_FROM="$1"; shift; R_TO="$1"; shift
fi
FILTER_RAW=("$@")              # vacío = todos los combos del veredicto
PIN_SH="$TURGALIUM_REPO/experiments/helpers/ligero36_pin.sh"
[ -f "$PIN_SH" ] || { echo "!! falta $PIN_SH" >&2; exit 3; }

case "$MODE" in
  # v2 (Prompt C 4.4): RPN_CTRL=64 → 128 procesos en 2 nodos, el MISMO tamaño que
  # la celda de control de la fase A (fase_a.sh:119: NT = SLURM_JOB_NUM_NODES × NPN
  # con NPN=64; control_cell fase_a.sh:112-122). RPN_CTRL=112 no tiene referencia
  # previa con la que comparar.
  pt2pt) RPN=1;   RPN_CTRL=64;  MSPEC="8:4194304"; TESTS=(latency bw)
         [ "$SLURM_JOB_NUM_NODES" = 2 ] || { echo "!! pt2pt requiere 2 nodos" >&2; exit 3; } ;;
  coll)  RPN=64;  RPN_CTRL=64;  MSPEC="262144"; TESTS=(allreduce alltoall)
         [ "$SLURM_JOB_NUM_NODES" = 8 ] || { echo "!! coll requiere 8 nodos" >&2; exit 3; } ;;
  *) echo "!! modo desconocido: $MODE" >&2; exit 2 ;;
esac
NT=$(( SLURM_JOB_NUM_NODES * RPN ))
NT_CTRL=$(( SLURM_JOB_NUM_NODES * RPN_CTRL ))
# D18: los SIETE pares disponibles (gcc rc/dc/ud/tcp; intel mlx/verbs/tcp)
COMBOS=( "gcc rc" "gcc dc" "gcc ud" "gcc tcp" "intel mlx" "intel verbs;ofi_rxm" "intel tcp" )

SCRIPT_SHA="$(sha256sum "$(readlink -f "$0")" | awk '{print $1}')"
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/ligero112/osu112-$MODE-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="osu112-$MODE-$SLURM_JOB_ID"
export LEVEL1_MODE="unprivileged"   # R14
CMDLOG="$TURGALIUM_REPO/instrumentation/cmdlog.sh"
mkdir -p "$CMDLOG_DIR" data/raw/ligero112

# v2 (Prompt C 4.5): interfaz TCP con la MISMA fuente y valor que en la fase A
# (fase_a.sh:125-127): primera interfaz ib*/ibs* con IPv4, fallback primera no-lo.
TCP_IFACE="$(ip -o -4 addr show | awk '$2 ~ /^(ib|ibs)/ {print $2; exit}')"
[ -n "${TCP_IFACE:-}" ] || TCP_IFACE="$(ip -o -4 addr show | awk '$2 != "lo" {print $2; exit}')"
echo "== interfaz tcp fijada: $TCP_IFACE (igual en ambas pilas; fase_a.sh:125-127)"

GROUP="$MODE-$SLURM_JOB_NODELIST"
echo "== osu112 job=$SLURM_JOB_ID grupo=$GROUP rondas=$R_FROM..$R_TO sha256=$SCRIPT_SHA $(date -Is)"
echo "== nodos asignados (fijos dentro de la asignación):"
srun --ntasks="$SLURM_JOB_NUM_NODES" --ntasks-per-node=1 hostname -s | sort | tr '\n' ' '; echo

osu_dir() { # $1 = pila; $2 = pt2pt|collective
  echo "$TURGALIUM_SCRATCH/benchmarks/osu/$1/spr/libexec/osu-micro-benchmarks/mpi/$2"
}
for p in "${COMBOS[@]}"; do set -- $p
  [ -x "$(osu_dir "$1" pt2pt)/osu_latency" ] || { echo "!! falta OSU $1 spr" >&2; exit 3; }
done

VERIF_CSV="$TURGALIUM_SCRATCH/cc/config/ligero112-verif.csv"
[ -f "$VERIF_CSV" ] || { echo "!! falta verificación funcional ($VERIF_CSV): lanzar ligero112_verif.sbatch antes" >&2; exit 3; }
combo_ok() { awk -F, -v p="$1" -v t="$2" '$1==p && $2==t && $6=="OK"' "$VERIF_CSV" | grep -q .; }

env_par() { # $1 = pila; $2 = transporte
  case "$1" in
    # v2 (Prompt C 4.5): réplica EXACTA del env_par de fase_a.sh:82-98 (líneas
    # 86-96 para el tcp: UCX_NET_DEVICES / FI_TCP_IFACE y sus unset al cambiar de
    # par); TCP_IFACE se fija arriba como en fase_a.sh:125-127.
    gcc)   module purge 2>/dev/null || true; module load openmpi_gcc/5.0.5 ucx/1.9.0
           # T05: la pila gcc NO fija I_MPI_PIN (antes lo exportaba a 0 y se colaba
           # en Intel por herencia del entorno, como en ligero36); se desactiva
           # explícitamente al limpiar el entorno de la celda
           export OMPI_MCA_pml=ucx UCX_TLS="${2},sm,self" UCX_LOG_LEVEL=info
           unset I_MPI_FABRICS FI_PROVIDER FI_TCP_IFACE I_MPI_DEBUG I_MPI_PIN I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true
           if [ "$2" = tcp ]; then
               export UCX_NET_DEVICES="$TCP_IFACE"
               export OMPI_MCA_opal_common_ucx_tls=any OMPI_MCA_opal_common_ucx_devices=any
           else
               unset UCX_NET_DEVICES 2>/dev/null || true
           fi ;;
    intel) module purge 2>/dev/null || true; module load intel/2025.3.2
           export I_MPI_FABRICS=ofi FI_PROVIDER="$2" I_MPI_DEBUG=5
           unset OMPI_MCA_pml UCX_TLS UCX_LOG_LEVEL UCX_NET_DEVICES OMPI_MCA_opal_common_ucx_tls OMPI_MCA_opal_common_ucx_devices 2>/dev/null || true
           if [ "$MODE" = coll ]; then
               # v2 (Prompt C 4.2): el pin de colectivas vive AQUÍ para que el
               # map-check y el run usen EXACTAMENTE el mismo entorno (antes solo
               # estaba en launch_and_wrap y el map-check corría sin pin)
               export I_MPI_PIN=1 I_MPI_PIN_PROCESSOR_LIST="0-31,56-87"
           else
               # T05: pin de Intel DESACTIVADO de forma EXPLÍCITA en pt2pt (antes
               # unset: el default de Intel podría pinear); el emplazamiento lo
               # hace PIN_SH con taskset, no Intel
               export I_MPI_PIN=0
               unset I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true
           fi
           if [ "$2" = tcp ]; then export FI_TCP_IFACE="$TCP_IFACE"; else unset FI_TCP_IFACE 2>/dev/null || true; fi ;;
  esac
}

transport_label() { # $1 = pila; $2 = run.log  (|| true: con pipefail, un grep sin
  case "$1" in         # match no debe matar la asignación — patrón de fase_b)
    gcc)   grep -oE 'inter-node cfg#[0-9]+ tag\([a-z_0-9/]+' "$2" | grep -oE 'tag\(.*' | sort -u | tr '\n' ' ' || true ;;
    intel) grep -m1 -oE 'libfabric provider[:= ]*[a-z_;]+' "$2" | head -1 || true ;;
  esac
}

detecta_pin_intel() { # $1 = run.log de Intel → exit 0 = pin de Intel ACTIVO (FALLO-PIN, T05)
  # Texto que distingue los logs reales (T05):
  #   CON pin:  «[0] MPI startup(): I_MPI_PIN=1» (+ I_MPI_PIN_PROCESSOR_LIST=…)
  #     data/raw/ligero/osu36-coll-83425/allreduce-intel-verbs;ofi_rxm-r2/run.log
  #   SIN pin:  «[0] MPI startup(): I_MPI_PIN=0»
  #     data/raw/ligero/osu36-pt2pt-83381/latency-intel-mlx-r1/run.log
  grep -qE "^\[[0-9]+\] MPI startup\(\): I_MPI_PIN=1" "$1"
}

launch_and_wrap() { # $1 = pila; $2 = transporte; resto: comando MPI completo (binario + args)
  local pila="$1" trans="$2"; shift 2
  case "$MODE:$pila" in
    pt2pt:gcc)   LAUNCH=(mpirun -np 2 --map-by ppr:1:node --bind-to none bash "$PIN_SH") ;;
    pt2pt:intel) LAUNCH=(mpirun -n 2 -ppn 1 bash "$PIN_SH") ;;
    coll:gcc)    LAUNCH=(mpirun -np "$NT" --map-by "ppr:$(( RPN / 2 )):package" --bind-to core) ;;
    coll:intel)  LAUNCH=(mpirun -n "$NT" -ppn "$RPN") ;;   # v2: el pin va en env_par (Prompt C 4.2)
  esac
  bash "$CMDLOG" "${LAUNCH[@]}" "$@"
}

control_cell() { # $1 = inicio|fin (D-B: allreduce 64 KiB, gcc por defecto)
  module purge 2>/dev/null || true; module load openmpi_gcc/5.0.5 ucx/1.9.0
  unset OMPI_MCA_pml UCX_TLS UCX_LOG_LEVEL OMPI_MCA_opal_common_ucx_tls OMPI_MCA_opal_common_ucx_devices 2>/dev/null || true
  unset I_MPI_FABRICS FI_PROVIDER FI_TCP_IFACE I_MPI_DEBUG I_MPI_PIN I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true
  unset UCX_NET_DEVICES 2>/dev/null || true
  local LP
  if [ "$MODE" = pt2pt ]; then LP=(mpirun -np "$NT_CTRL" --map-by "ppr:$RPN_CTRL:node" --bind-to core)
  else LP=(mpirun -np "$NT_CTRL" --map-by "ppr:$(( RPN_CTRL / 2 )):package" --bind-to core); fi
  echo "--- control D-B ($1): osu_allreduce -m 65536 ($NT_CTRL ranks, gcc por defecto)"
  if ! bash "$CMDLOG" "${LP[@]}" "$(osu_dir gcc collective)/osu_allreduce" -m 65536 \
      > "$CMDLOG_DIR/control-$1.log" 2>&1; then
    echo "!! FALLO control $1 (conservado en control-$1.log)"
  fi
}

MAPCHECK='echo "$(hostname -s) rank=${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-${SLURM_PROCID:-NA}}} cpus=$(taskset -pc $$ | awk "{print \$NF}")"'
map_check() { # $1 = pila; $2 = transporte (mapa coll: RPN/nodo)
  env_par "$1" "$2"
  case "$MODE:$1" in
    coll:gcc)    mpirun -np "$NT" --map-by "ppr:$(( RPN / 2 )):package" --bind-to core bash -c "$MAPCHECK" ;;
    coll:intel)  mpirun -n "$NT" -ppn "$RPN" bash -c "$MAPCHECK" ;;
    pt2pt:gcc)   mpirun -np "$NT" --map-by ppr:1:node --bind-to none bash "$PIN_SH" bash -c "$MAPCHECK" ;;
    pt2pt:intel) mpirun -n "$NT" -ppn 1 bash "$PIN_SH" bash -c "$MAPCHECK" ;;
  esac > "$CMDLOG_DIR/mapcheck-$1-$2.txt" 2>&1 || echo "!! map-check FALLO $1/$2 (conservado)"
  echo "   map-check $1/$2: $(grep -c 'cpus=' "$CMDLOG_DIR/mapcheck-$1-$2.txt" || echo 0) ranks"
}

MANIFEST="$CMDLOG_DIR/manifest.csv"
echo "job,grupo,ronda,celda,par,ranks,exit_code,verificacion,transporte,runlog" > "$MANIFEST"

run_osu() { # $1 = pila; $2 = transporte; $3 = test; $4 = ronda
  local pila="$1" trans="$2" test="$3" ronda="$4" ec verif lbl
  # v2 (Prompt C 4.3): alltoall gcc/tcp a 512 ranks NO MEDIBLE en modo usuario
  # (E40, DEVIATIONS 2026-10-03; fase_a.sh:12 «(P-4): no se ejecuta» y el salto
  # de fase_a.sh:187-189): SALTADA-declarada, sin ejecución y sin consumir rondas.
  if [ "$MODE" = coll ] && [ "$pila" = gcc ] && [ "$trans" = tcp ] && [ "$test" = alltoall ]; then
    echo "--- RUN $test par=$pila/$trans ronda=$ronda ranks=$NT SALTADA-declarada (E40) $(date -Is)"
    echo "$SLURM_JOB_ID,$GROUP,$ronda,$test,$pila/$trans,$NT,na,SALTADA-declarada,na,-" >> "$MANIFEST"
    return 0
  fi
  local bin
  bin="$(osu_dir "$pila" "$([ "$MODE" = pt2pt ] && echo pt2pt || echo collective)")/osu_$test"
  [ -x "$bin" ] || { echo "!! falta $bin" >&2; exit 3; }
  local rundir="$CMDLOG_DIR/$test-$pila-$trans-r$(( 10#$ronda ))"
  mkdir -p "$rundir"
  echo "--- RUN $test par=$pila/$trans ronda=$ronda ranks=$NT $(date -Is)"
  env_par "$pila" "$trans"   # módulos y transporte DEL RUN (fase_b run_mpi); sin esto,
                             # la ronda hereda el entorno del último map-check (bug 83365:
                             # gcc/rc lanzado con el mpirun de Intel MPI, ranks locales)
  if launch_and_wrap "$pila" "$trans" "$bin" -m "$MSPEC" > "$rundir/run.log" 2>&1; then ec=0; else ec=$?; fi
  if [ "$ec" -eq 0 ] && grep -q "# OSU MPI" "$rundir/run.log"; then verif=OK; else verif=FALLO; fi
  lbl="$(transport_label "$pila" "$rundir/run.log")"; lbl="${lbl:-sin-observar}"
  # T05: un pin de Intel NO deseado en un run pt2pt invalida la celda
  if [ "$pila" = intel ] && [ "$MODE" = pt2pt ] && detecta_pin_intel "$rundir/run.log"; then verif=FALLO-PIN; fi
  echo "    -> exit=$ec verif=$verif transporte=$lbl"
  echo "$SLURM_JOB_ID,$GROUP,$ronda,$test,$pila/$trans,$NT,$ec,$verif,$lbl,$rundir/run.log" >> "$MANIFEST"
}

# --- gate de verificación funcional: combos activos y saltados declarados -----
ACTIVE=()
if [ ${#FILTER_RAW[@]} -eq 0 ]; then
  CANDIDATES=()
  for combo in "${COMBOS[@]}"; do
    set -- $combo
    CANDIDATES+=("$1" "$2")
  done
else
  CANDIDATES=("${FILTER_RAW[@]}")
fi
i=0
while [ $i -lt ${#CANDIDATES[@]} ]; do
  p="${CANDIDATES[$i]} ${CANDIDATES[$((i+1))]}"
  i=$((i+2))
  set -- $p
  if combo_ok "$1" "$2"; then ACTIVE+=("$p")
  else
    echo "!! SALTAADA $1/$2: sin verificación funcional OK (no consume rondas)"
    echo "$SLURM_JOB_ID,$GROUP,0,na,$1/$2,na,na,SALTAADA-noverif,na,-" >> "$MANIFEST"
  fi
done
[ "${#ACTIVE[@]}" -gt 0 ] || { echo "!! todas las combinaciones saltadas" >&2; exit 4; }

# --- asignación: control inicial, map-checks, rondas intercaladas, control final
control_cell inicio
for p in "${ACTIVE[@]}"; do set -- $p; map_check "$1" "$2"; done
for r in $(seq "$R_FROM" "$R_TO"); do
  echo "== RONDA $r $(date -Is)"
  for p in "${ACTIVE[@]}"; do
    set -- $p
    for t in "${TESTS[@]}"; do
      run_osu "$1" "$2" "$t" "$r"
    done
  done
done
control_cell fin
echo "== osu112 $GROUP ($R_FROM..$R_TO) terminado (job $SLURM_JOB_ID) $(date -Is)"
echo "== manifiesto: $MANIFEST"
VALIDADOR="$TURGALIUM_REPO/experiments/lib/valida_job.sh"
if bash "$VALIDADOR" "$CMDLOG_DIR"; then
  :
else
  case "$?" in
    1) echo "VEREDICTO: REVISAR" ;;
    *) echo "VALIDADOR-NO-EJECUTADO" ;;
  esac
fi
