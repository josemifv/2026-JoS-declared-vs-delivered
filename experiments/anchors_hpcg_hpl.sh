#!/usr/bin/env bash
# Anclas del antes/después — SOLO HPCG, UNA sesión (decisión de la persona,
# DEVIATIONS 2026-10-05: HPL fuera del estudio, R6 desactivada, reparto en dos
# días de R11 eliminado; el contraste temporal del estudio es CMMSE vs ahora).
#
# Diseño aprobado: configuración CMMSE VERBATIM (R4, extraída de
# ~/CMMSE26/scripts/hpcg_{gcc,intel}.sh) — 104³ local, 60 s de ejecución (no oficial),
# 448 ranks = 8 nodos × 56/nodo; stack del CMMSE y stack ACTUAL, 11 rondas
# intercaladas entre ambos stacks (1 calentamiento + 10 efectivas por stack),
# control D-B al inicio y fin, 8 nodos SMT-off (--exclude=b9p02,b9p12),
# nivel 1 unprivileged (R14), map-check por celda (R10), verificación por el
# informe HPCG-Benchmark_*.txt del rundir, NUNCA por stdout (hallazgo 83403).
#   Orden de las DOS PILAS ALTERNADO POR RONDA (DEVIATIONS 2026-10-05: el orden fijo
#   de las fases A/B es una limitación — gcc/rc siempre 2.º sale ≈4,5 % y no es
#   separable del transporte): rondas impares cmmse-gcc→actual-gcc→cmmse-intel→actual-intel;
#   rondas pares, orden inverso. Dentro de cada pila, vintage según lista.
#   CMMSE gcc  : módulos gcc/11.2.0 openmpi_gcc/5.0.5; binario ~/CMMSE26/benchmarks/hpcg/install-gcc/xhpcg
#   ACTUAL gcc : módulos openmpi_gcc/5.0.5 ucx/1.9.0;  binario de fase B (stack actual)
#   CMMSE intel: módulo intel/2025.3.2;                binario ~/CMMSE26/benchmarks/hpcg/install-intel/xhpcg
#   ACTUAL intel: módulo intel/2025.3.2 (mismo);       binario de fase B (stack actual)
#   Lanzamiento CMMSE (R4): gcc  = mpirun --mca pml ucx -x UCX_TLS=rc_mlx5,ud_mlx5,sm
#                                   -x UCX_NET_DEVICES=mlx5_0:1 -n 448 --map-by node --bind-to core
#                             intel= mpirun -genv FI_PROVIDER mlx -genv I_MPI_FABRICS ofi -n 448 -ppn 56
#   Transporte por celda = primario del CMMSE (rc_mlx5 / mlx), idéntico en cmmse y
#   actual: entre vintages solo cambia el software, no cómo se lanza. El transporte
#   EFECTIVO por run se observa con UCX_LOG_LEVEL=info (gcc) e I_MPI_DEBUG=5 (intel):
#   solo verbosidad de observación, no cambia selección de transporte ni binding.
#   COMPILADOR DE HPCG (declarar, R5): cmmse-intel = icx+MKL (binario del CMMSE);
#   actual-intel = g++ vía Intel MPI (binario de fase B). Los dos gcc: gfortran.
#   Rutas del CMMSE verificadas con ls real (2026-10-05): install-gcc/xhpcg e
#   install-intel/xhpcg existen (también build-*/bin/xhpcg; se usan los install-*).
#   Nodos concretos del CMMSE (R4.5) no identificados: se declara al lanzar; la
#   asignación usa 8 nodos SMT-off cualesquiera, identidad registrada.
# Trazabilidad: REPO_COMMIT se lee de .deploy-commit (escrito al desplegar desde
# el portátil); si no existe, git rev-parse del clon.
# Duración estimada: 44 runs × ~2,4 min (medido en matriz y CMMSE) ≈ 1,8 h + controles → --time=03:00:00.
# Uso:  mkdir -p data/raw/anchors   # el .out lo abre slurmctld AL ENVIAR
#	sbatch --nodes=8 --exclude=b9p02,b9p12 --time=03:00:00 experiments/anchors_hpcg_hpl.sh [r_to]
#	r_to = última ronda a ejecutar (defecto 11; humo QA = 1)
#SBATCH --job-name=cc-anchor
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --nodes=8
#SBATCH --output=data/raw/anchors/%x-%j.out
#SBATCH --time=03:00:00

set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env

[ "$SLURM_JOB_NUM_NODES" = 8 ] || { echo "!! las anclas se definen a 8 nodos (R4)" >&2; exit 3; }
NPN=56; NPROCS=$(( SLURM_JOB_NUM_NODES * NPN ))
R_TO="${1:-11}"   # última ronda (humo QA: 1)
case "$R_TO" in 1|11) ;; *) echo "!! r_to solo 1 (humo) u 11 (medida)" >&2; exit 2 ;; esac

# --- §8: trazabilidad de la asignación ---------------------------------------
SCRIPT_SHA="$(sha256sum "$(readlink -f "$0")" | awk '{print $1}')"
REPO_COMMIT="$(awk '{print $1}' .deploy-commit 2>/dev/null || true)"
# 3ª auditoría (1c): el despliegue escribe el hash COMPLETO de rev-parse HEAD;
# se valida el formato y, si no cumple, se cae al git del clon o a "desconocido"
echo "$REPO_COMMIT" | grep -qE '^[0-9a-f]{7,40}$' || REPO_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo 'desconocido (clon no alineado)')"
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/anchors/anchor-hpcg-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="anchor-hpcg-$SLURM_JOB_ID"
export LEVEL1_MODE="unprivileged"   # R14, registrado en clusters/turgalium.md
CMDLOG="$TURGALIUM_REPO/instrumentation/cmdlog.sh"
L1="$TURGALIUM_REPO/instrumentation/level1_capture.sh"
[ -x "$CMDLOG" ] && [ -f "$L1" ] || { echo "!! falta instrumentación" >&2; exit 3; }
mkdir -p "$CMDLOG_DIR" data/raw/anchors

CMMSE_HOME="${CMMSE_HOME:-$HOME/CMMSE26}"
XHPCG_CMMSE_GCC="$CMMSE_HOME/benchmarks/hpcg/install-gcc/xhpcg"
XHPCG_CMMSE_INTEL="$CMMSE_HOME/benchmarks/hpcg/install-intel/xhpcg"
XHPCG_ACT_GCC="$TURGALIUM_SCRATCH/benchmarks/phaseB/hpcg/gcc/xhpcg"
XHPCG_ACT_INTEL="$TURGALIUM_SCRATCH/benchmarks/phaseB/hpcg/intel/xhpcg"

CELLS=( cmmse-gcc actual-gcc cmmse-intel actual-intel )
for c in "${CELLS[@]}"; do
  case "$c" in
    cmmse-gcc)   BIN="$XHPCG_CMMSE_GCC" ;;
    cmmse-intel) BIN="$XHPCG_CMMSE_INTEL" ;;
    actual-gcc)  BIN="$XHPCG_ACT_GCC" ;;
    actual-intel) BIN="$XHPCG_ACT_INTEL" ;;
  esac
  [ -x "$BIN" ] || { echo "!! falta binario $c: $BIN" >&2; exit 3; }
done

env_cell() { # $1 = celda — entorno R4 verbatim por celda
  module purge 2>/dev/null || true
  case "$1" in
    cmmse-gcc)   # HALLAZGO 83737 (humo, declarado/real): el módulo gcc/11.2.0 del
                 # CMMSE YA NO EXISTE en el clúster (module spider: no encontrado).
                 # El ldd del binario prueba que NO aporta nada al runtime: libmpi
                 # resuelve a openmpi_gcc/5.0.5 (igual que en el CMMSE) y libstdc++
                 # a /lib64; sin libgfortran ni libopenblas dinámicas (BLAS estática).
                 # Se carga SOLO openmpi_gcc/5.0.5 (el MPI del CMMSE, íntegro).
                 module load openmpi_gcc/5.0.5
                 # OpenBLAS 0.3.27 autocompilado del CMMSE (así lo lanzaba el CMMSE:
                 # LD_LIBRARY_PATH a su install; auditoría 2026-10-05: faltaba)
                 export LD_LIBRARY_PATH="$CMMSE_HOME/benchmarks/openblas/install/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
                 unset I_MPI_FABRICS FI_PROVIDER I_MPI_DEBUG I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true ;;
    actual-gcc)  module load openmpi_gcc/5.0.5 ucx/1.9.0
                 unset I_MPI_FABRICS FI_PROVIDER I_MPI_DEBUG I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true ;;
    cmmse-intel|actual-intel) module load intel/2025.3.2
                 unset OMPI_MCA_pml UCX_TLS UCX_LOG_LEVEL 2>/dev/null || true ;;
  esac
}

launch_cell() { # $1 = celda — array LAUNCH según R4 (igual en cmmse y actual);
  case "$1" in   # UCX_LOG_LEVEL/I_MPI_DEBUG = observación del transporte efectivo (ver cabecera)
    *-gcc)   LAUNCH=(mpirun --mca pml ucx
                     -x UCX_TLS=rc_mlx5,ud_mlx5,sm
                     -x UCX_NET_DEVICES=mlx5_0:1
                     -x UCX_LOG_LEVEL=info
                     -n "$NPROCS" --map-by node --bind-to core) ;;
    *-intel) LAUNCH=(mpirun -genv FI_PROVIDER mlx
                     -genv I_MPI_FABRICS ofi
                     -genv I_MPI_DEBUG 5
                     -n "$NPROCS" -ppn "$NPN") ;;
  esac
}

cell_bin() {
  case "$1" in
    cmmse-gcc) echo "$XHPCG_CMMSE_GCC" ;;
    actual-gcc) echo "$XHPCG_ACT_GCC" ;;
    cmmse-intel) echo "$XHPCG_CMMSE_INTEL" ;;
    actual-intel) echo "$XHPCG_ACT_INTEL" ;;
  esac
}

echo "== ancla HPCG job=$SLURM_JOB_ID (una sesión: cmmse vs actual, 11 rondas intercaladas) sha256=$SCRIPT_SHA $(date -Is)"
echo "== commit(desplegado): $REPO_COMMIT"
echo "== nodos asignados (R4.5: nodos del CMMSE no identificados — se declara):"
srun --ntasks="$SLURM_JOB_NUM_NODES" --ntasks-per-node=1 bash -c \
     'echo "$(hostname -s) SMT=$(lscpu | awk "/Thread\(s\) per core/ {print \$4}")"' | sort | tr '\n' ' '; echo

MAPCHECK='echo "$(hostname -s) rank=${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-${SLURM_PROCID:-NA}}} cpus=$(taskset -pc $$ | awk "{print \$NF}")"'

control_cell() { # $1 = inicio|fin — D-B: allreduce 64 KiB, gcc por defecto, 512 ranks
  module purge 2>/dev/null || true; module load openmpi_gcc/5.0.5 ucx/1.9.0
  unset OMPI_MCA_pml UCX_TLS UCX_LOG_LEVEL I_MPI_FABRICS FI_PROVIDER I_MPI_DEBUG I_MPI_PIN_PROCESSOR_LIST 2>/dev/null || true
  local NT=$(( SLURM_JOB_NUM_NODES * 64 ))
  echo "--- control D-B ($1): osu_allreduce -m 65536 ($NT ranks, gcc por defecto)"
  if ! bash "$CMDLOG" mpirun -np "$NT" --map-by "ppr:32:package" --bind-to core \
        "$TURGALIUM_SCRATCH/benchmarks/osu/gcc/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce" -m 65536 \
        > "$CMDLOG_DIR/control-$1.log" 2>&1; then
    echo "!! FALLO control $1 (conservado en control-$1.log)"
  fi
}

# hpcg.dat del CMMSE: OBLIGATORIO (R4 verbatim, sin fallback — 3ª auditoría, bloque C)
HPDAT="$CMMSE_HOME/benchmarks/hpcg/configs/hpcg.dat"
[ -f "$HPDAT" ] || { echo "!! falta el hpcg.dat del CMMSE: $HPDAT (R4 verbatim; sin fallback)" >&2; exit 3; }
HPDAT_SHA="$(sha256sum "$HPDAT" | awk '{print $1}')"
echo "== hpcg.dat del CMMSE: sha256=$HPDAT_SHA"

MANIFEST="$CMDLOG_DIR/manifest.csv"
echo "job,ronda,celda,exit_code,verificacion,gflops,runlog,compilador,hpcg_dat_sha256" > "$MANIFEST"

bash "$L1" start
bash "$L1" pre
control_cell inicio

for c in "${CELLS[@]}"; do   # map-check R10 + ldd + module list POR CELDA (bloque C)
  env_cell "$c"; launch_cell "$c"
  bin="$(cell_bin "$c")"
  echo "--- celda $c: module list + ldd + map-check"
  module list > "$CMDLOG_DIR/modules-$c.txt" 2>&1 || true
  ldd "$bin" > "$CMDLOG_DIR/ldd-$c.txt" 2>&1 || true
  # libmpi/libucp/libopenblas cargadas por el binario (QA 7b)
  grep -E "libmpi|libucp|libopenblas" "$CMDLOG_DIR/ldd-$c.txt" || echo "!! ldd $c sin libmpi/ucp/openblas"
  "${LAUNCH[@]}" bash -c "$MAPCHECK" > "$CMDLOG_DIR/mapcheck-$c.txt" 2>&1 \
    || echo "!! map-check FALLO $c (conservado)"
  echo "   map-check $c: $(grep -c 'cpus=' "$CMDLOG_DIR/mapcheck-$c.txt" || echo 0) ranks"
done

for r in $(seq 1 "$R_TO"); do
  # 3ª auditoría (bloque C): orden de las DOS PILAS ALTERNADO por ronda
  if [ "$(( 10#$r % 2 ))" = 1 ]; then ORDEN=("${CELLS[@]}"); else ORDEN=("${CELLS[3]}" "${CELLS[2]}" "${CELLS[1]}" "${CELLS[0]}"); fi
  echo "== RONDA $r (orden: ${ORDEN[*]}) $(date -Is)$( [ "$r" = 1 ] && echo '  (calentamiento: ambas pilas)' )"
  for c in "${ORDEN[@]}"; do
    env_cell "$c"; launch_cell "$c"
    bin="$(cell_bin "$c")"
    RD="$CMDLOG_DIR/$c-r$(( 10#$r ))"; mkdir -p "$RD"
    cp "$HPDAT" "$RD/hpcg.dat"   # R4 verbatim: el del CMMSE, sin fallback
    ec="$( cd "$RD" && { if bash "$CMDLOG" "${LAUNCH[@]}" "$bin" > run.log 2>&1; then echo 0; else echo $?; fi; } )"
    # Verificación por el informe txt del rundir, no por stdout (DEVIATIONS 2026-10-05)
    txt="$RD/HPCG-Benchmark_"*.txt
    if grep -qE "HPCG[[:space:]]+result[[:space:]]+is[[:space:]]+VALID" "$RD/run.log" 2>/dev/null \
       || { ls $txt >/dev/null 2>&1 && grep -q "HPCG result is VALID" $txt; }; then v=VALID
    elif grep -qE "HPCG[[:space:]]+result[[:space:]]+is[[:space:]]+INVALID" "$RD/run.log" 2>/dev/null \
       || { ls $txt >/dev/null 2>&1 && grep -q "HPCG result is INVALID" $txt; }; then v=INVALID
    else v="NO-VERIFICADO"; fi
    # 3ª auditoría (bloque C): regex soporta "of=423.43" y "of 423.43" (-i)
    gf="$(grep -h -ioE "GFLOP/s rating of=?[[:space:]]*[0-9.]+" $txt 2>/dev/null | head -1 | grep -oE '[0-9.]+[0-9]' || true)"
    case "$c" in
      cmmse-gcc) COMP="gfortran (gcc/11.2.0 CMMSE; módulo desaparecido, runtime sistema)" ;;
      actual-gcc) COMP="gfortran (fase B)" ;;
      cmmse-intel) COMP="icx+MKL (CMMSE)" ;; actual-intel) COMP="g++ vía Intel MPI (fase B)" ;;
    esac
    echo "    -> $c exit=$ec verif=$v gflops=${gf:--} comp=$COMP"
    echo "$SLURM_JOB_ID,$r,$c,$ec,$v,${gf:--},$RD/run.log,$COMP,$HPDAT_SHA" >> "$MANIFEST"
  done
done

control_cell fin
bash "$L1" post
bash "$L1" stop
echo "== ancla HPCG (rondas 1-$R_TO de 11; $([ "$R_TO" = 1 ] && echo HUMO QA || echo medida)) terminada (job $SLURM_JOB_ID) $(date -Is) — $MANIFEST"
