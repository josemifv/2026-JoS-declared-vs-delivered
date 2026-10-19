#!/usr/bin/env bash
# Fase B IntelC v1 — matriz adicional D21 (T14, confirmado 2026-10-08).
# Base exacta: experiments/fase_b.sh en HEAD; sha256 e847876a2051c326d07a12a2b66d2f2c8c857a6ff7649fd5e16d4489a85de8b5.
# La cadena 83717-83725 corrió la versión c1f5b26332773e9a0786f31b83c42ee82772aa44,
# sha256 94966c95696eb13c607fcee02f01fcd892abfaa76a4899af8eafe07ffff0e77e.
# Entre ambas solo cambió la validación de formato de .deploy-commit (d7a0293);
# no cambia lo que se mide. Esta copia implementa D21: intel/mlx + intelc/mlx.
# Grupos de asignación (cada sbatch = una asignación de rondas completas ≤ 3 h, P-5):
#   ep_ft r_from r_to: NPB EP y FT (11 rondas)
#   cg r_from r_to   : NPB CG, rondas r_from..r_to (11 en total: 1 calentamiento + 10 efectivas)
#   mg r_from r_to   : NPB MG, ídem
#   hpcg             : HPCG 8 nodos, 2 pares, 11 rondas (10 efectivas)
# Pares D21: intel/mlx (gfortran + Intel MPI) e intelc/mlx (ifx/icpx + Intel MPI).
# Orden por ronda: intel primero en rondas impares; intelc primero en rondas pares.
# Reps: 11 rondas (1 calentamiento + 10 efectivas; R1) en NPB y HPCG; sin STREAM (D20).
# NOTA (DEVIATIONS 2026-10-04, [D]): la v2 de este script aplicó un recorte R13-1
# (NPB 10→5) sin veredicto de presupuesto que lo justificara y sin aprobación de la
# persona; la persona lo rechazó al detectarlo y las rondas 7-11 se completan en
# asignaciones adicionales (mismo script, sin nivel 1, como toda la matriz).
# Cada run: salida registrada (cmdlog), verificación de resultado (NPB
# "Verification = SUCCESSFUL"; HPCG "HPCG result is VALID") y transporte mlx
# observado por Intel MPI. Los runs no
# verificados se conservan y etiquetan; NUNCA se mezclan con las válidas (orden de la
# persona, 2026-10-04). Cabecera con commit del repo y sha256 del script (§8).
#
# v5 (DEVIATIONS 2026-10-05, [D] auditoría): BUG de ejecución en v1-v4 — rpn se
# calculaba como nt/nodos_de_la_asignación, así que en asignaciones de 8 nodos las
# celdas «1n/2n/4n» corrieron con 64/128/256 ranks REPARTIDOS en 8 nodos (8/16/32
# ranks/nodo; confirmado por los hostnames de los run.log de ep-1n-intel-r1 de
# 83314: b9p03,06,07,08,09,10,11,13), y el map-check de humo verificaba otro mapa
# (64 r/n). Corrección: rpn = NPN SIEMPRE (64/nodo); una celda solo corre si su
# tamaño coincide EXACTAMENTE con la asignación (nt = SLURM_JOB_NUM_NODES × NPN);
# el humo/map-check verifica el mapa REAL con el que corre cada celda.
# Las celdas 1n/2n/4n de 83314-83318 y 83405-83407 se REPITEN con asignaciones
# del tamaño correcto (--nodes=1, 2, 4, en serie); las 8n son válidas.
# Uso: las asignaciones aprobadas están en los lanzamientos L9a/L9b; cada una
# usa el tamaño exacto de la celda y conserva 64 ranks por nodo.
# El humo L9a ejecuta una ronda por carga/talla y el lanzamiento está documentado en launch/.
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
GROUP="${1:?grupo: ep_ft | cg r_from r_to | mg r_from r_to | hpcg}"
R_FROM="${2:-1}"; R_TO="${3:-11}"
NPN=64

# --- §8: trazabilidad de la asignación ---------------------------------------
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_SHA="$(sha256sum "$SCRIPT_PATH" | awk '{print $1}')"
REPO_COMMIT="$(awk '{print $1}' .deploy-commit 2>/dev/null || true)"
# 3ª auditoría (1c): el despliegue escribe el hash COMPLETO de rev-parse HEAD;
# se valida el formato y, si no cumple, se cae al git del clon o a "desconocido"
echo "$REPO_COMMIT" | grep -qE '^[0-9a-f]{7,40}$' || REPO_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo 'desconocido (clon no alineado)')"
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
NPB_INTEL="$TURGALIUM_SCRATCH/benchmarks/npb/intel/spr"
NPB_INTELC="$TURGALIUM_SCRATCH/benchmarks/npb/intelc/spr"
HPCG_INTEL="$TURGALIUM_SCRATCH/benchmarks/phaseB/hpcg/intel/xhpcg"
HPCG_INTELC="$TURGALIUM_SCRATCH/benchmarks/phaseB/hpcg/intelc/xhpcg"
MAP64="$(seq -s, 0 31),$(seq -s, 56 87)"   # 64 ranks/nodo: 32 por socket en bloques
MAPCHECK='echo "$(hostname -s) rank=${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-${SLURM_PROCID:-NA}}} cpus=$(taskset -pc $$ | awk "{print \$NF}")"'
NEED_NPB=0; NEED_HPCG=0
case "$GROUP" in ep_ft|cg|mg) NEED_NPB=1;; hpcg) NEED_HPCG=1;; *) echo "!! grupo desconocido: $GROUP" >&2; exit 2;; esac

if [ "$NEED_NPB" = 1 ]; then
  for b in ep ft; do
    for d in "$NPB_INTEL" "$NPB_INTELC"; do
      [ -x "$d/$b.D.x" ] || { echo "!! falta binario $d/$b.D.x" >&2; exit 3; }
    done
  done
fi
[ "$NEED_HPCG" = 0 ] || { [ -x "$HPCG_INTEL" ] && [ -x "$HPCG_INTELC" ] || { echo "!! falta binario HPCG ($HPCG_INTEL | $HPCG_INTELC)" >&2; exit 3; }; }

launch_setup() { # $1 = pila; $2 = ranks totales; $3 = ranks por nodo
  local nt="$2" rpn="$3"
  case "$1" in
    gcc)   LAUNCH=(mpirun -np "$nt" --map-by "ppr:$(( rpn / 2 )):package" --bind-to core) ;;
    intel|intelc) export I_MPI_PIN_PROCESSOR_LIST="$MAP64"
           LAUNCH=(mpirun -n "$nt" -ppn "$rpn") ;;
  esac
}

env_par() { # $1 = pila; $2 = transporte
  case "$1" in
    gcc)   module purge 2>/dev/null || true; module load openmpi_gcc/5.0.5 ucx/1.9.0
           export OMPI_MCA_pml=ucx UCX_TLS="${2},sm,self" UCX_LOG_LEVEL=info
           unset I_MPI_FABRICS FI_PROVIDER I_MPI_DEBUG I_MPI_PMI_LIBRARY I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true ;;
    intel|intelc) module purge 2>/dev/null || true; module load intel/2025.3.2
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

# transporte efectivo por run: proveedor libfabric observado por Intel MPI.
transport_label() { # $1 = pila; $2 = run.log
  case "$1" in
    gcc)   echo "sin-observar" ;;
    intel|intelc) local prov
           prov="$(grep -m1 -oE 'libfabric provider[:= ]*[a-z_]+' "$2" | head -1 || true)"
           echo "${prov:-sin-observar}" ;;
  esac
}

verify_label() { # $1 = tipo (npb|hpcg); $2 = run.log
# Patrones tolerantes a espacios: NPB imprime " Verification    =               SUCCESSFUL"
# y los patrones literales de la v1 etiquetaban todo como NO-VERIFICADO.
  case "$1" in
    npb)  if grep -qE "Verification[[:space:]]*=[[:space:]]*UNSUCCESSFUL" "$2"; then echo "UNSUCCESSFUL"
          elif grep -qE "Verification[[:space:]]*=[[:space:]]*SUCCESSFUL" "$2"; then echo "SUCCESSFUL"
          else echo "NO-VERIFICADO"; fi ;;
    hpcg) # Este binario NO escribe el resultado por stdout (run.log termina en el
          # arranque MPI; hallazgo 83403, DEVIATIONS 2026-10-05): el resultado está en
          # el informe HPCG-Benchmark_*.txt del rundir; se verifica por ahí.
          local d txt
          d="$(dirname "$2")"
          txt=( "$d"/HPCG-Benchmark_*.txt )
          if grep -qE "HPCG[[:space:]]+result[[:space:]]+is[[:space:]]+VALID" "$2" \
             || { [ -f "${txt[0]}" ] && grep -q "HPCG result is VALID" "${txt[@]}"; }; then echo "VALID"
          elif grep -qE "HPCG[[:space:]]+result[[:space:]]+is[[:space:]]+INVALID" "$2" \
             || { [ -f "${txt[0]}" ] && grep -q "HPCG result is INVALID" "${txt[@]}"; }; then echo "INVALID"
          else echo "NO-VERIFICADO"; fi ;;
  esac
}

MANIFEST="$CMDLOG_DIR/manifest.csv"
echo "job,grupo,ronda,celda,par,ranks,exit_code,verificacion,transporte,runlog" > "$MANIFEST"

run_mpi() { # $1 = pila; $2 = transporte; $3 = tipo; $4 = celda; $5 = ronda; $6 = ranks; $7 = binario; $8... = args
  local pila="$1" trans="$2" tipo="$3" cell="$4" ronda="$5" nt="$6" bin="$7"; shift 7
  local rpn="$NPN"   # v5: SIEMPRE 64 ranks/nodo (bug v1-v4: rpn = nt/nodos repartía
  #                 las celdas 1n/2n/4n entre los 8 nodos de la asignación)
  if [ "$nt" -ne $(( SLURM_JOB_NUM_NODES * NPN )) ]; then
    echo "!! SALTADA $cell/$pila ronda $ronda: la celda pide $nt ranks y la asignación da $(( SLURM_JOB_NUM_NODES * NPN )) (rpn=NPN fijo; la asignación debe ser del tamaño de la celda, v5)"
    echo "$SLURM_JOB_ID,$GROUP,$ronda,$cell,$pila/$trans,$nt,0,SALTADA,-," >> "$MANIFEST"   # v5.2: las saltadas constan
    return 0
  fi
  env_par "$pila" "$trans"
  launch_setup "$pila" "$nt" "$rpn"
  local rundir="$CMDLOG_DIR/$cell-$pila-$trans-r$(( 10#$ronda ))" ec verif trans_lbl   # v5.2: el TRANSPORTE en el rundir (cada par en su directorio)
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

PAIRS=( "intel mlx" "intelc mlx" )
SIZES_NPB=( 1 2 4 8 )
case "$GROUP" in
  ep_ft) KERNELS_NPB="ep ft" ;;
  cg) KERNELS_NPB="cg" ;;
  mg) KERNELS_NPB="mg" ;;
  *) KERNELS_NPB="" ;;
esac

# --- humo por asignación: transporte efectivo + mapa pedido = real, POR CELDA
# (v5: el map-check verifica el mapa EXACTO con el que corren las celdas de esta
# asignación: nt = nodos_asignados × NPN; antes verificaba 64 r/n en cada talla,
# mapa que no era el de las celdas 1n/2n/4n — [D] auditoría 2026-10-05)
control_cell inicio
NT_ASSIG=$(( SLURM_JOB_NUM_NODES * NPN ))
if [ "$NEED_NPB" = 1 ]; then
  for p in "${PAIRS[@]}"; do
    set -- $p; env_par "$1" "$2"
    launch_setup "$1" "$NT_ASSIG" "$NPN"
    map_check "humo-$1-$2-${SLURM_JOB_NUM_NODES}n"
    # QA b (checklist): la libmpi enlazada debe corresponder al mpirun cargado —
    # ldd del binario REAL de CADA kernel de este grupo (2ª auditoría: no solo ep)
    bd="$NPB_INTEL"; if [ "$1" = intelc ]; then bd="$NPB_INTELC"; fi
    : > "$CMDLOG_DIR/ldd-$1.txt"
    for k in $KERNELS_NPB; do
      echo "== $k.D.x (mpirun: $(command -v mpirun))" >> "$CMDLOG_DIR/ldd-$1.txt"
      ldd "$bd/$k.D.x" 2>/dev/null | grep -E "libmpi|libfabric" >> "$CMDLOG_DIR/ldd-$1.txt" || echo "(sin libmpi/libfabric)" >> "$CMDLOG_DIR/ldd-$1.txt"
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
  ep_ft)
    for r in $(seq "$R_FROM" "$R_TO"); do
      echo "== RONDA $r $(date -Is)"
      # NPB EP y FT: 4 tamaños × 2 pares, todas las rondas.
      ROUND_PAIRS=( "${PAIRS[@]}" )
      if (( r % 2 == 0 )); then ROUND_PAIRS=( "${PAIRS[1]}" "${PAIRS[0]}" ); fi
      for s in "${SIZES_NPB[@]}"; do
        for p in "${ROUND_PAIRS[@]}"; do
          set -- $p
          d="$NPB_INTEL"; [ "$1" = intelc ] && d="$NPB_INTELC"
          run_mpi "$1" "$2" npb "ep-${s}n" "$r" $(( s * NPN )) "$d/ep.D.x"
          run_mpi "$1" "$2" npb "ft-${s}n" "$r" $(( s * NPN )) "$d/ft.D.x"
        done
      done
    done ;;
  cg|mg)
    for r in $(seq "$R_FROM" "$R_TO"); do
      echo "== RONDA $r $(date -Is)"
      ROUND_PAIRS=( "${PAIRS[@]}" )
      if (( r % 2 == 0 )); then ROUND_PAIRS=( "${PAIRS[1]}" "${PAIRS[0]}" ); fi
      for s in "${SIZES_NPB[@]}"; do
        for p in "${ROUND_PAIRS[@]}"; do
          set -- $p
          d="$NPB_INTEL"; [ "$1" = intelc ] && d="$NPB_INTELC"
          run_mpi "$1" "$2" npb "$GROUP-${s}n" "$r" $(( s * NPN )) "$d/$GROUP.D.x"
        done
      done
    done ;;
  hpcg)
    for r in $(seq "$R_FROM" "$R_TO"); do
      echo "== RONDA $r $(date -Is)"
      ROUND_PAIRS=( "${PAIRS[@]}" )
      if (( r % 2 == 0 )); then ROUND_PAIRS=( "${PAIRS[1]}" "${PAIRS[0]}" ); fi
      for p in "${ROUND_PAIRS[@]}"; do
        set -- $p
        d="$HPCG_INTEL"; [ "$1" = intelc ] && d="$HPCG_INTELC"
        run_mpi "$1" "$2" hpcg "hpcg-8n" "$r" $(( 8 * NPN )) "$d"
      done
    done ;;
esac

control_cell fin
echo "== fase B $GROUP ($R_FROM..$R_TO) terminada (job $SLURM_JOB_ID) $(date -Is)"
echo "== manifiesto: $MANIFEST"
