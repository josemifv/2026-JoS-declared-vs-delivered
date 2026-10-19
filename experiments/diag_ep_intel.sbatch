#!/usr/bin/env bash
# Diagnóstico de NIVEL 2 (R7, dirigido) de la anomalía EP con Intel MPI — v3
# (DEVIATIONS 2026-10-06 D15): repetición en las condiciones EXACTAS de la fase B.
# El diagnóstico previo (83800, v2) usó el pin por defecto (intel 2 cpus/rank,
# gcc 1 core/rank) y NO reprodujo el binding de la matriz; con 1 rank intel ≈ gcc
# (0,98×: 44,5 frente a 45,6 s) y la caída (0,64-0,74×) solo aparece con 64 ranks.
# NO es una medida del estudio: diagnóstico de una celda; no entra en fichas ni rankings.
# Diseño (D15, autorizado 2026-10-06): 1 nodo, ≤ 30 min, binarios REALES de fase B
# (ep.D.x, los de la matriz), 3 casos × 2 repeticiones:
#   gcc   64r : binding EXACTO de fase_b.sh — mpirun -np 64 --map-by ppr:32:package
#               --bind-to core, UCX_TLS=rc,sm,self (par gcc/rc de la matriz)
#   intel 64r : binding EXACTO de fase_b.sh — I_MPI_FABRICS=ofi FI_PROVIDER=mlx
#               I_MPI_DEBUG=5 I_MPI_PIN_PROCESSOR_LIST=0-31,56-87 (MAP64),
#               mpirun -n 64 -ppn 64
#   intel 32r : ídem con 32 ranks (los primeros 32 cpus de la lista = paquete 0
#               compacto, 1 core/rank — contraste con los 64)
# Por rank: cpu MHz muestreada CADA 5 s durante toda la ejecución (/sys cpufreq,
# en background a un fichero por rank — v3.1, Prompt C 6.3), hilos
# (/proc/<pid>/status Threads), afinidad real (taskset), utime de hijos con
# `times` en el MISMO shell del wait (v3.1, Prompt C 6.2; el $() de v3 daba
# utime_children=0 siempre) y rank con defaults anidados (Prompt C 6.1).
# ldd de ambos ep.D.x y env del módulo intel.
#SBATCH --job-name=cc-diag-ep
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --nodes=1
#SBATCH --output=data/raw/diag/%x-%j.out
#SBATCH --time=00:20:00

set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}" || exit 1
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env

REPO_COMMIT="$(awk '{print $1}' .deploy-commit 2>/dev/null || true)"
echo "$REPO_COMMIT" | grep -qE '^[0-9a-f]{7,40}$' || REPO_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo 'desconocido (clon no alineado)')"
SCRIPT_SHA="$(sha256sum "$(readlink -f "$0")" | awk '{print $1}')"
CMDLOG="$TURGALIUM_REPO/instrumentation/cmdlog.sh"
[ -x "$CMDLOG" ] || { echo "!! falta cmdlog" >&2; exit 3; }
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/diag/ep-v3-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="diag-ep-v3-$SLURM_JOB_ID"
mkdir -p "$CMDLOG_DIR" data/raw/diag

# Binarios REALES de fase B (los de la matriz; ep.D.x)
EP_D_GCC="$TURGALIUM_SCRATCH/benchmarks/npb/gcc/spr/ep.D.x"
EP_D_INTEL="$TURGALIUM_SCRATCH/benchmarks/npb/intel/spr/ep.D.x"
[ -x "$EP_D_GCC" ] && [ -x "$EP_D_INTEL" ] || { echo "!! faltan ep.D.x de fase B" >&2; exit 3; }

# Sonda por rank: el binario EP corre en background y se muestrea /proc mientras
# corre; utime en ticks al exit vía `times` (exacto, sin carrera — v2, humo 83734),
# hilos de status, afinidad de taskset y cpu MHz muestreada de /sys cpufreq en las
# primeras cpus de la máscara del rank (dos tomas: al arrancar y a 1 s).
SONDA='cat > ep_probe.sh <<"EOF"
#!/usr/bin/env bash
set -uo pipefail
# $1 = binario EP — lo lanza el rank (env heredado del rank: binding incluido)
mhz() { for c in $(echo "$1" | tr "," "\n" | head -6); do
          printf "%s " "$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq 2>/dev/null || echo NA)"; done; }
expand() { for r in $(echo "$1" | tr "," " "); do
             case "$r" in *-*) a="${r%-*}"; b="${r#*-}"; seq "$a" "$b";; *) echo "$r";; esac; done; }
# v3.1 (Prompt C 6.1): rank con los mismos defaults anidados que el MAPCHECK
R="${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-${SLURM_PROCID:-?}}}"
"$1" & PID=$!
sleep 0.05
TH="$(grep Threads /proc/$PID/status 2>/dev/null | awk "{print \$2}")"
AF="$(taskset -pc $PID 2>/dev/null | awk "{print \$NF}")"
AFX="$(expand "$AF" | head -6 | tr "\n" "," )"; AFX="${AFX%,}"
# v3.1 (Prompt C 6.3): muestreo de scaling_cur_freq de las CPUs del rank CADA 5 s
# durante TODA la ejecución, en segundo plano, a un fichero por rank (antes solo
# t0 y t+1 s). Se arranca DESPUÉS de conocer AFX: el subshell hereda una copia de
# las variables en el fork y no vería asignaciones posteriores del padre.
( while kill -0 $PID 2>/dev/null; do
    echo "$(date +%s) $(mhz "$AFX" 2>/dev/null)" >> "freq-rank-$R.log"
    sleep 5
  done ) 2>/dev/null &
FS=$!
MH1="$(mhz "$AFX")"
sleep 1
MH2="$(mhz "$AFX")"
T1=$(awk "{print \$14}" /proc/$PID/stat 2>/dev/null)   # última muestra viva
wait $PID; RC=$?
kill "$FS" 2>/dev/null || true; wait "$FS" 2>/dev/null || true
# v3.1 (Prompt C 6.2): `times` en el MISMO shell que hizo el wait (a un fichero
# temporal) y se lee después; con $() el subshell devolvía utime_children=0 siempre.
TMPF="./utime-times-$$-r$R.txt"
times > "$TMPF" 2>/dev/null
CHU="$(tail -n1 "$TMPF" | awk "{print \$1}")"
rm -f "$TMPF"
echo "rank=$R pid=$PID exit=$RC threads=${TH:-?} affinity=${AF:-?} mhz_t0=${MH1:-?} mhz_t1s=${MH2:-?} utime_ticks=${T1:-NA} utime_children=${CHU:-NA} freq_file=freq-rank-$R.log"
exit $RC
EOF
chmod +x ep_probe.sh'

echo "== diagnóstico EP v3 job=$SLURM_JOB_ID nodo=$(hostname -s) sha256=$SCRIPT_SHA $(date -Is)"
echo "== commit(desplegado): $REPO_COMMIT"
echo "== condiciones EXACTAS de la matriz de fase B (D15): binarios ep.D.x;"

diagnose() { # $1 = pila; $2 = módulos; $3 = binario; $4 = ranks; $5 = modo binding
  local pila="$1" mods="$2" bin="$3" ranks="$4" modo="$5" rep EC LOG
  echo "--- PILA $pila EP.D ranks=$ranks binding=$modo (2 repeticiones)"
  module purge 2>/dev/null || true
  module load $mods
  { echo "## module list"; module list 2>&1 || true
    echo "## ldd $bin"; ldd "$bin" 2>&1 | grep -E "libgfortran|libm\.|libmpi|libucp|libfabric" || true
    echo "## env del módulo"; env | grep -E "^(LD_LIBRARY_PATH|LD_PRELOAD|I_MPI_|FI_|UCX_|OMP_)" | sort || true
  } > "$CMDLOG_DIR/env-libs-$pila-${ranks}r.txt" 2>&1
  for rep in 1 2; do
    LOG="$CMDLOG_DIR/ep-$pila-${ranks}r-$modo-r$rep.log"
    case "$modo" in
      gccB)   # EXACTO fase_b.sh (gcc/rc): env_par gcc + launch_setup gcc con nt=64
              export OMPI_MCA_pml=ucx UCX_TLS="rc,sm,self" UCX_LOG_LEVEL=info
              unset I_MPI_FABRICS FI_PROVIDER I_MPI_DEBUG I_MPI_PIN I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true
              if bash "$CMDLOG" mpirun -np "$ranks" --map-by "ppr:32:package" --bind-to core \
                   bash ./ep_probe.sh "$bin" > "$LOG" 2>&1; then EC=0; else EC=$?; fi ;;
      intelB) # EXACTO fase_b.sh (intel/mlx): env_par intel + launch_setup intel
              export I_MPI_FABRICS=ofi FI_PROVIDER=mlx I_MPI_DEBUG=5
              unset OMPI_MCA_pml UCX_TLS UCX_LOG_LEVEL 2>/dev/null || true
              # misma lista MAP64; con 32 ranks ocupa el paquete 0 (cpus 0-31, 1 core/rank)
              export I_MPI_PIN_PROCESSOR_LIST="0-31,56-87"
              if bash "$CMDLOG" mpirun -n "$ranks" -ppn "$ranks" \
                   bash ./ep_probe.sh "$bin" > "$LOG" 2>&1; then EC=0; else EC=$?; fi ;;
    esac
    echo "    rep$rep: exit=$EC | $(grep -m1 'Time in seconds' "$LOG" || echo 'sin Time') | $(grep -m1 'Mop/s total' "$LOG" || echo 'sin Mops')"
    grep "^rank=" "$LOG" | head -2 || echo "    (sin líneas de rank: EP no llegó a arrancar)"
  done
}

cd "$CMDLOG_DIR" || exit 3
bash -c "$SONDA"   # instala ep_probe.sh en el rundir

# Casos (D15): gcc 64r (ppr:32:package), intel 64r (MAP64), intel 32r (MAP64);
# 2 repeticiones por caso. Sin ep.C: el caso 1 rank ya está medido en 83800
# (44,5 vs 45,6 s; D14) y las condiciones de interés son las de la matriz.
diagnose gcc   "openmpi_gcc/5.0.5 ucx/1.9.0" "$EP_D_GCC"   64 gccB
diagnose intel "intel/2025.3.2"              "$EP_D_INTEL" 64 intelB
diagnose intel "intel/2025.3.2"              "$EP_D_INTEL" 32 intelB

echo "== fin diagnóstico v3 (job $SLURM_JOB_ID) $(date -Is) — $CMDLOG_DIR"
echo "NOTA: diagnóstico de NIVEL 2 (R7): solo la celda EP anomalía; no entra en fichas ni rankings."
