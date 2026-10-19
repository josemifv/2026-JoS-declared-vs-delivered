# ============================================================================
# REFERENCIA (no usar para lanzar): fase_b.sh v4 — la versión más cercana
# commiteada a la que corrieron 83405-83407 (sha c9358acf…, IRRECUPERABLE: sin
# copia de Slurm, sin historial git en el clúster; el .out solo guarda el sha).
# Esta copia es la de e110a87 (sha 70a6bb57); el delta con la ejecutada fue el
# estado sin commitear del 2026-10-04. Registrado en DEVIATIONS 2026-10-05.
# ============================================================================
#!/usr/bin/env bash
# Fase B — Bloque 1: matriz de microbenchmarks (plan v2 §3-§5, confirmado 2026-10-04).
# Grupos de asignación (cada sbatch = una asignación de rondas completas ≤ 3 h, P-5):
#   stream_ep_ft : STREAM (1 nodo, ambas pilas, 11 rondas) + NPB EP y FT (11 rondas)
#   ep_ft r_from r_to: NPB EP y FT (mismo bucle que stream_ep_ft, SIN STREAM; para
#                  completar rondas de NPB — [O]: cambio operativo, no cambia lo medido)
#   cg r_from r_to   : NPB CG, rondas r_from..r_to (11 en total: 1 calentamiento + 10 efectivas)
#   mg r_from r_to   : NPB MG, ídem
#   hpcg             : HPCG 8 nodos, 4 pares, 11 rondas (10 efectivas)
# Pares (R2, orden a priori registrado): intel/mlx, gcc/rc, gcc/dc, gcc/ud.
# Reps: 11 rondas (1 calentamiento + 10 efectivas; R1) en STREAM y en los 4 kernels.
# NOTA (DEVIATIONS 2026-10-04, [D]): la v2 de este script aplicó un recorte R13-1
# (NPB 10→5) sin veredicto de presupuesto que lo justificara y sin aprobación de la
# persona; la persona lo rechazó al detectarlo y las rondas 7-11 se completan en
# asignaciones adicionales (mismo script, sin nivel 1, como toda la matriz).
# Cada run: salida registrada (cmdlog), verificación de resultado (NPB
# "Verification = SUCCESSFUL"; HPCG "HPCG result is VALID") y de transporte efectivo
# (lanes UCX inter-node para gcc; proveedor libfabric para intel). Los runs no
# verificados se conservan y etiquetan; NUNCA se mezclan con las válidas (orden de la
# persona, 2026-10-04). Cabecera con commit del repo y sha256 del script (§8).
#
# Uso (desde la raíz del checkout del repo en el clúster):
#   sbatch --nodes=8 --exclude=b9p02,b9p12 --time=02:30:00 experiments/fase_b.sh stream_ep_ft
#   sbatch --nodes=8 --exclude=b9p02,b9p12 --time=02:00:00 experiments/fase_b.sh cg 1 3
#   sbatch --nodes=8 --exclude=b9p02,b9p12 --time=02:45:00 experiments/fase_b.sh mg 1 3
#   sbatch --nodes=8 --exclude=b9p02,b9p12 --time=02:15:00 experiments/fase_b.sh hpcg
# Prueba de 1 nodo (las celdas que piden más nodos de los asignados se saltan con aviso):
#   sbatch --nodes=1 --time=00:25:00 experiments/fase_b.sh stream_ep_ft 1 1
#SBATCH --job-name=cc-faseB
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --time=02:30:00
#SBATCH --output=data/raw/phaseB/faseB-%x-%j.out

set -euo pipefail
# Bajo sbatch, $0 es la copia en /var/lib/slurmd (fallo del job 83292): el
# checkout es el directorio de envío (SLURM_SUBMIT_DIR); en uso manual, el cwd.
cd "${SLURM_SUBMIT_DIR:-$PWD}"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env
GROUP="${1:?grupo: stream_ep_ft | ep_ft | cg r_from r_to | mg r_from r_to | hpcg}"
R_FROM="${2:-1}"; R_TO="${3:-11}"
NPN=64

# --- §8: trazabilidad de la asignación ---------------------------------------
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_SHA="$(sha256sum "$SCRIPT_PATH" | awk '{print $1}')"
REPO_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo 'desconocido (clon no alineado)')"
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/phaseB/faseB-$GROUP-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="faseB-$GROUP-$SLURM_JOB_ID"
export LEVEL1_MODE="unprivileged"   # R14, registrado en clusters/turgalium.md
CMDLOG="$(pwd)/instrumentation/cmdlog.sh"   # ABSOLUTO: la rama hpcg hace `cd "$rundir"
# antes de invocarlo; con la ruta relativa, todos sus runs morían con 127 (job 83319)
[ -x "$CMDLOG" ] || { echo "!! falta wrapper $CMDLOG" >&2; exit 3; }
mkdir -p "$CMDLOG_DIR" data/raw/phaseB

echo "== job $SLURM_JOB_ID grupo=$GROUP rondas=$R_FROM..$R_TO inicia $(date -Is)"
echo "== script: $SCRIPT_PATH"
echo "== sha256(script): $SCRIPT_SHA"
echo "== commit(repo):  $REPO_COMMIT"
echo "== nodos asignados (fijos dentro de la asignación):"
srun --ntasks="$SLURM_JOB_NUM_NODES" --ntasks-per-node=1 hostname -s | sort | tr '\n' ' '; echo

# --- binarios y mapa ----------------------------------------------------------
NPB_GCC="$TURGALIUM_SCRATCH/benchmarks/npb/gcc/spr"
NPB_INTEL="$TURGALIUM_SCRATCH/benchmarks/npb/intel/spr"
HPCG_GCC="$TURGALIUM_SCRATCH/benchmarks/phaseB/hpcg/gcc/xhpcg"
HPCG_INTEL="$TURGALIUM_SCRATCH/benchmarks/phaseB/hpcg/intel/xhpcg"
STREAM_GCC="$TURGALIUM_SCRATCH/benchmarks/stream/gcc/stream_spr"
STREAM_INTEL="$TURGALIUM_SCRATCH/benchmarks/stream/intel/stream_spr"
# (STREAM = OpenMP, fuente única en $TURGALIUM_SCRATCH/src/stream/stream.c; se
# compila por pila con -fopenmp -O3 -march=sapphirerapids vía compile_stream.sbatch;
# hilos pineados al mismo mapa explícito que los ranks MPI: GOMP_CPU_AFFINITY / KMP_AFFINITY.)
MAP64="$(seq -s, 0 31),$(seq -s, 56 87)"   # 64 ranks/nodo: 32 por socket en bloques
MAPSP="$(seq -s ' ' 0 31) $(seq -s ' ' 56 87)"
MAPCHECK='echo "$(hostname -s) rank=${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-${SLURM_PROCID:-NA}}} cpus=$(taskset -pc $$ | awk "{print \$NF}")"'
NEED_NPB=0; NEED_HPCG=0; NEED_STREAM=0
case "$GROUP" in stream_ep_ft) NEED_NPB=1; NEED_STREAM=1;; ep_ft) NEED_NPB=1;; cg|mg) NEED_NPB=1;; hpcg) NEED_HPCG=1;; *) echo "!! grupo desconocido: $GROUP" >&2; exit 2;; esac

if [ "$NEED_NPB" = 1 ]; then
  for b in ep ft; do
    for d in "$NPB_GCC" "$NPB_INTEL"; do
      [ -x "$d/$b.D.x" ] || { echo "!! falta binario $d/$b.D.x" >&2; exit 3; }
    done
  done
fi
[ "$NEED_HPCG" = 0 ] || { [ -x "$HPCG_GCC" ] && [ -x "$HPCG_INTEL" ] || { echo "!! falta binario HPCG ($HPCG_GCC | $HPCG_INTEL)" >&2; exit 3; }; }
if [ "$NEED_STREAM" = 1 ]; then
  [ -x "$STREAM_GCC" ] || { echo "!! falta binario $STREAM_GCC (compilar con compile_stream.sbatch)" >&2; exit 3; }
  [ -x "$STREAM_INTEL" ] || { echo "!! falta binario $STREAM_INTEL (compilar con compile_stream.sbatch)" >&2; exit 3; }
fi

launch_setup() { # $1 = pila; $2 = ranks totales; $3 = ranks por nodo
  local nt="$2" rpn="$3"
  case "$1" in
    gcc)   LAUNCH=(mpirun -np "$nt" --map-by "ppr:$(( rpn / 2 )):package" --bind-to core) ;;
    intel) export I_MPI_PIN_PROCESSOR_LIST="$MAP64"
           LAUNCH=(mpirun -n "$nt" -ppn "$rpn") ;;
  esac
}

env_par() { # $1 = pila; $2 = transporte
  case "$1" in
    gcc)   module purge 2>/dev/null || true; module load openmpi_gcc/5.0.5 ucx/1.9.0
           export OMPI_MCA_pml=ucx UCX_TLS="${2},sm,self" UCX_LOG_LEVEL=info
           unset I_MPI_FABRICS FI_PROVIDER I_MPI_DEBUG I_MPI_PMI_LIBRARY I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true ;;
    intel) module purge 2>/dev/null || true; module load intel/2025.3.2
           export I_MPI_FABRICS=ofi FI_PROVIDER="$2" I_MPI_DEBUG=5
           unset OMPI_MCA_pml UCX_TLS UCX_LOG_LEVEL 2>/dev/null || true ;;
  esac
}

map_check() { # $1 = etiqueta
  echo "--- map-check $1 (pedido: $MAP64 en ${SLURM_JOB_NUM_NODES}n)"
  "${LAUNCH[@]}" bash -c "$MAPCHECK" > "$CMDLOG_DIR/mapcheck-$1.txt" 2>&1 \
    || echo "!! map-check FALLO $1 (conservado en mapcheck-$1.txt)"
  grep -c 'cpus=' "$CMDLOG_DIR/mapcheck-$1.txt" || echo "!! map-check sin ranks $1"
}

# transporte efectivo por run (punto 7): lanes inter-node UCX (gcc) o provider (intel)
transport_label() { # $1 = pila; $2 = run.log
  case "$1" in
    gcc)   local lanes
           lanes="$(grep -oE 'inter-node cfg#[0-9]+ tag\([a-z_0-9/]+' "$2" | grep -oE 'tag\(.*' | sort -u | tr '\n' ' ' || true)"
           echo "${lanes:-sin-observar}" ;;
    intel) local prov
           prov="$(grep -m1 -oE 'libfabric provider[:= ]*[a-z_]+' "$2" | head -1 || true)"
           echo "${prov:-sin-observar}" ;;
  esac
}

verify_label() { # $1 = tipo (npb|hpcg|stream); $2 = run.log
# Patrones tolerantes a espacios: NPB imprime " Verification    =               SUCCESSFUL"
# y el STREAM usado imprime "Solution Validates: avg error less than 1e-13..." (sin "yes");
# los patrones literales de la v1 etiquetaban todo como NO-VERIFICADO (humo 83304).
  case "$1" in
    npb)  if grep -qE "Verification[[:space:]]*=[[:space:]]*UNSUCCESSFUL" "$2"; then echo "UNSUCCESSFUL"
          elif grep -qE "Verification[[:space:]]*=[[:space:]]*SUCCESSFUL" "$2"; then echo "SUCCESSFUL"
          else echo "NO-VERIFICADO"; fi ;;
    hpcg) # Este binario NO escribe el resultado por stdout (run.log termina en el
          # arranque MPI; hallazgo 83403, DEVIATIONS 2026-10-05): el resultado está en
          # el informe HPCG-Benchmark_*.txt del rundir; se verifica por ahí.
          local d txt
          d="$(dirname "$2")"
          txt="$d/HPCG-Benchmark_"*.txt
          if grep -qE "HPCG[[:space:]]+result[[:space:]]+is[[:space:]]+VALID" "$2" \
             || { ls $txt >/dev/null 2>&1 && grep -q "HPCG result is VALID" $txt; }; then echo "VALID"
          elif grep -qE "HPCG[[:space:]]+result[[:space:]]+is[[:space:]]+INVALID" "$2" \
             || { ls $txt >/dev/null 2>&1 && grep -q "HPCG result is INVALID" $txt; }; then echo "INVALID"
          else echo "NO-VERIFICADO"; fi ;;
    stream) if grep -q "Solution Validates:" "$2"; then echo "VALIDA"
            else echo "NO-VERIFICADO"; fi ;;
  esac
}

MANIFEST="$CMDLOG_DIR/manifest.csv"
echo "job,grupo,ronda,celda,par,ranks,exit_code,verificacion,transporte,runlog" > "$MANIFEST"

run_mpi() { # $1 = pila; $2 = transporte; $3 = tipo; $4 = celda; $5 = ronda; $6 = ranks; $7 = binario; $8... = args
  local pila="$1" trans="$2" tipo="$3" cell="$4" ronda="$5" nt="$6" bin="$7"; shift 7
  local rpn=$(( nt / SLURM_JOB_NUM_NODES ))
  if [ "$rpn" -eq 0 ]; then rpn=1; fi
  if [ "$nt" -gt $(( SLURM_JOB_NUM_NODES * NPN )) ]; then
    echo "!! SALTADA $cell/$pila ronda $ronda: pide $nt ranks > asignados"; return 0
  fi
  env_par "$pila" "$trans"
  launch_setup "$pila" "$nt" "$rpn"
  local rundir="$CMDLOG_DIR/$cell-$pila-r$(( 10#$ronda ))" ec verif trans_lbl
  mkdir -p "$rundir"
  echo "--- RUN $cell par=$pila/$trans ronda=$ronda ranks=$nt $(date -Is)"
  if [ "$tipo" = hpcg ]; then
    ec="$( cd "$rundir" \
      && printf "HPCG benchmark input file\nSandia National Laboratories; University of Tennessee, Knoxville\n104 104 104\n60\n" > hpcg.dat \
      && { if bash "$CMDLOG" "${LAUNCH[@]}" "$bin" > run.log 2>&1; then echo 0; else echo $?; fi; } )"
  else
    ec="$( { if bash "$CMDLOG" "${LAUNCH[@]}" "$bin" "$@" > "$rundir/run.log" 2>&1; then echo 0; else echo $?; fi; } )"
  fi
  verif="$(verify_label "$tipo" "$rundir/run.log")"
  trans_lbl="$(transport_label "$pila" "$rundir/run.log")"
  echo "    -> exit=$ec verif=$verif transporte=$trans_lbl"
  echo "$SLURM_JOB_ID,$GROUP,$ronda,$cell,$pila/$trans,$nt,$ec,$verif,$trans_lbl,$rundir/run.log" >> "$MANIFEST"
}

run_stream() { # $1 = pila; $2 = ronda — STREAM OpenMP 64 hilos, mapa explícito por pila
  local pila="$1" ronda="$2" ec verif bin rundir
  module purge 2>/dev/null || true
  if [ "$pila" = gcc ]; then
    module load openmpi_gcc/5.0.5 ucx/1.9.0
    export OMP_NUM_THREADS=64 GOMP_CPU_AFFINITY="$MAPSP"
    bin="$STREAM_GCC"
  else
    module load intel/2025.3.2
    export OMP_NUM_THREADS=64 KMP_AFFINITY="granularity=core,explicit,proclist=[$MAP64],proc_bind=explicit"
    bin="$STREAM_INTEL"
  fi
  rundir="$CMDLOG_DIR/stream-$pila-r$(( 10#$ronda ))"
  mkdir -p "$rundir"
  echo "--- RUN stream par=$pila ronda=$ronda hilos=64 (mapa $MAP64) $(date -Is)"
  ec="$( { if bash "$CMDLOG" "$bin" > "$rundir/run.log" 2>&1; then echo 0; else echo $?; fi; } )"
  verif="$(verify_label stream "$rundir/run.log")"
  echo "    -> exit=$ec verif=$verif"
  echo "$SLURM_JOB_ID,$GROUP,$ronda,stream,$pila,64,$ec,$verif,omp-mapa,$rundir/run.log" >> "$MANIFEST"
}

control_cell() { # $1 = inicio|fin  (D-B: allreduce 64 KiB, gcc por defecto, 512 ranks)
  module purge 2>/dev/null || true; module load openmpi_gcc/5.0.5 ucx/1.9.0
  unset OMPI_MCA_pml UCX_TLS UCX_LOG_LEVEL I_MPI_FABRICS FI_PROVIDER I_MPI_DEBUG I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true
  local NT=$(( SLURM_JOB_NUM_NODES * NPN ))
  echo "--- control D-B ($1): osu_allreduce -m 65536 ($NT ranks, gcc por defecto)"
  launch_setup gcc "$NT" "$NPN"
  if ! bash "$CMDLOG" "${LAUNCH[@]}" "$TURGALIUM_SCRATCH/benchmarks/osu/gcc/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce" -m 65536 > "$CMDLOG_DIR/control-$1.log" 2>&1; then
    echo "!! FALLO control $1 (conservado en control-$1.log)"
  fi
}

PAIRS=( "intel mlx" "gcc rc" "gcc dc" "gcc ud" )
SIZES_NPB=( 1 2 4 8 )

# --- humo por asignación: transporte efectivo + mapa pedido = real, por par y tamaño
control_cell inicio
if [ "$NEED_NPB" = 1 ]; then
  for s in "${SIZES_NPB[@]}"; do
    [ "$s" -le "$SLURM_JOB_NUM_NODES" ] || continue
    for p in "${PAIRS[@]}"; do
      set -- $p; env_par "$1" "$2"
      launch_setup "$1" $(( s * NPN )) "$NPN"
      map_check "humo-$1-$2-${s}n"
    done
  done
fi
if [ "$NEED_HPCG" = 1 ]; then
  for p in "${PAIRS[@]}"; do
    set -- $p; env_par "$1" "$2"
    launch_setup "$1" $(( 8 * NPN )) "$NPN"
    map_check "humo-$1-$2-8n"
  done
fi

# --- rondas intercaladas ------------------------------------------------------
case "$GROUP" in
  stream_ep_ft|ep_ft)
    for r in $(seq "$R_FROM" "$R_TO"); do
      echo "== RONDA $r $(date -Is)"
      if [ "$GROUP" = stream_ep_ft ]; then
        run_stream gcc "$r"
        run_stream intel "$r"
      fi
      # NPB EP y FT: 4 tamaños × 4 pares, todas las rondas (tope R13-1 eliminado:
      # no había veredicto de presupuesto que lo justificara ni aprobación — [D])
      for s in "${SIZES_NPB[@]}"; do
        for p in "${PAIRS[@]}"; do
          set -- $p
          d="$NPB_GCC"; [ "$1" = intel ] && d="$NPB_INTEL"
          run_mpi "$1" "$2" npb "ep-${s}n" "$r" $(( s * NPN )) "$d/ep.D.x"
          run_mpi "$1" "$2" npb "ft-${s}n" "$r" $(( s * NPN )) "$d/ft.D.x"
        done
      done
    done ;;
  cg|mg)
    for r in $(seq "$R_FROM" "$R_TO"); do
      echo "== RONDA $r $(date -Is)"
      for s in "${SIZES_NPB[@]}"; do
        for p in "${PAIRS[@]}"; do
          set -- $p
          d="$NPB_GCC"; [ "$1" = intel ] && d="$NPB_INTEL"
          run_mpi "$1" "$2" npb "$GROUP-${s}n" "$r" $(( s * NPN )) "$d/$GROUP.D.x"
        done
      done
    done ;;
  hpcg)
    for r in $(seq "$R_FROM" "$R_TO"); do
      echo "== RONDA $r $(date -Is)"
      for p in "${PAIRS[@]}"; do
        set -- $p
        d="$HPCG_GCC"; [ "$1" = intel ] && d="$HPCG_INTEL"
        run_mpi "$1" "$2" hpcg "hpcg-8n" "$r" $(( 8 * NPN )) "$d"
      done
    done ;;
esac

control_cell fin
echo "== fase B $GROUP ($R_FROM..$R_TO) terminada (job $SLURM_JOB_ID) $(date -Is)"
echo "== manifiesto: $MANIFEST"
