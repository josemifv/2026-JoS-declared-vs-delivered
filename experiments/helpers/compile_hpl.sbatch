#!/usr/bin/env bash
# ============================================================================
#  *** OBSOLETO, NO USAR *** (decisión de la persona, DEVIATIONS 2026-10-05):
#  HPL queda FUERA del estudio (anclas y R6 desactivada); NO compilar. El
#  contraste con el CMMSE se hace solo con HPCG. Se conserva sin borrar.
# ============================================================================
# Compila HPL 2.3 con el stack ACTUAL para las celdas «actual» de las anclas
# (R5.2: cada ancla se ejecuta dos veces — stack CMMSE vs actual).
#   [PROPUESTO POR EL AGENTE, pendiente de aprobación: no hay entrada previa que
#   fije los binarios HPL «actual». Parámetros derivados de la entrada R5.1-R5.2
#   (2026-10-02) y de la configuración CMMSE verificada el 2026-10-05.]
#
# Misma fuente (hpl-2.3 de ~/CMMSE26, árbol intacto: se copia a scratch) y la
# MISMA BLAS que la celda CMMSE; solo cambia el compilador/MPI:
#   gcc   : GCC del sistema 11.5 + openmpi_gcc/5.0.5 + ucx/1.9.0 + OpenBLAS 0.3.27
#           autocompilado (~/CMMSE26/benchmarks/openblas/install) — enlazado
#           directo, sin el módulo roto openblas/0.3.10.
#   intel : intel/2025.3.2 (mpiicx + MKL) — mismo módulo que el CMMSE.
# Makefiles generados desde los Make.gcc_openblas / Make.intel_mkl del CMMSE
# (mismas flags: -O3 -march=native -fomit-frame-pointer [+ -funroll-loops gcc]),
# sustituyendo TOPdir/ARCH/LAdir. Autotest pequeño con 2 ranks al final.
# Uso: sbatch --time=00:30:00 experiments/helpers/compile_hpl.sbatch <gcc|intel>
#SBATCH --job-name=cc-compile-hpl
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --nodes=1
#SBATCH --output=data/raw/anchors/%x-%j.out
#SBATCH --time=00:30:00

set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env

STACK="${1:?uso: compile_hpl.sbatch <gcc|intel>}"
CMMSE_HOME="${CMMSE_HOME:-$HOME/CMMSE26}"
SRC="$CMMSE_HOME/benchmarks/hpl/src/hpl-2.3"
BUILD="$TURGALIUM_SCRATCH/benchmarks/anchors/hpl/src/hpl-2.3"
INSTALL="$TURGALIUM_SCRATCH/benchmarks/anchors/hpl/$STACK/bin"
[ -d "$SRC" ] || { echo "!! falta fuente CMMSE: $SRC" >&2; exit 3; }

SCRIPT_SHA="$(sha256sum "$(readlink -f "$0")" | awk '{print $1}')"
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/anchors/compile-hpl-$STACK-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="compile-hpl-$STACK-$SLURM_JOB_ID"
export LEVEL1_MODE="unprivileged"   # R14
CMDLOG="$TURGALIUM_REPO/instrumentation/cmdlog.sh"
[ -x "$CMDLOG" ] || { echo "!! falta wrapper $CMDLOG" >&2; exit 3; }
mkdir -p "$CMDLOG_DIR"

echo "== compile_hpl job=$SLURM_JOB_ID stack=$STACK sha256=$SCRIPT_SHA $(date -Is)"

module purge 2>/dev/null || true
case "$STACK" in
  gcc)   module load openmpi_gcc/5.0.5 ucx/1.9.0
         FROM="Make.gcc_openblas"; TO="Make.actual_gcc"; ARCH="actual_gcc"
         SED=( -e "s|^ARCH         = .*|ARCH         = actual_gcc|" \
               -e "s|^TOPdir       = .*|TOPdir       = $BUILD|" \
               -e "s|^LAdir        = .*|LAdir        = $CMMSE_HOME/benchmarks/openblas/install|" ) ;;
  intel) module load intel/2025.3.2
         FROM="Make.intel_mkl"; TO="Make.actual_intel"; ARCH="actual_intel"
         SED=( -e "s|^ARCH         = .*|ARCH         = actual_intel|" \
               -e "s|^TOPdir       = .*|TOPdir       = $BUILD|" ) ;;
  *) echo "!! stack desconocido: $STACK (gcc|intel)" >&2; exit 2 ;;
esac
sed "${SED[@]}" "$SRC/$FROM" > "$CMDLOG_DIR/$TO.new"
grep -q "^ARCH" "$CMDLOG_DIR/$TO.new" || { echo "!! Make generado vacío" >&2; exit 3; }

rm -rf "$BUILD"
mkdir -p "$(dirname "$BUILD")"
cp -a "$SRC" "$BUILD"   # copia PRISTINA; el árbol CMMSE no se toca
cp "$CMDLOG_DIR/$TO.new" "$BUILD/$TO"

( cd "$BUILD" && make arch="$ARCH" -j 8 > "$CMDLOG_DIR/make.out" 2>&1 ) \
  || { echo "!! fallo make (conservado en make.out)"; tail -20 "$CMDLOG_DIR/make.out"; exit 4; }

mkdir -p "$INSTALL"
cp "$BUILD/bin/$ARCH/xhpl" "$INSTALL/xhpl"
[ -x "$INSTALL/xhpl" ] || { echo "!! no se instaló el binario" >&2; exit 4; }

# Autotest: 2 ranks, problema pequeño (mismo NB=192)
AT="$CMDLOG_DIR/autotest"; mkdir -p "$AT"
printf "HPLinpack benchmark input file\nInnovative Computing Laboratory, University of Tennessee\nHPL.out      output file name (if any)\n6            device out (6=stdout,7=stderr,file)\n1            # of problems sizes (N)\n8192         Ns\n1            # of NBs\n192          NBs\n0            PMAP process mapping (0=Row-,1=Column-major)\n1            # of process grids (P x Q)\n1            Ps\n2            Qs\n16.0         threshold\n1            # of panel fact\n2            PFACTs (0=left, 1=Crout, 2=Right)\n1            # of recursive stopping criterium\n4            NBMINs (>= 1)\n1            # of panels in recursion\n2            NDIVs\n1            # of recursive panel fact.\n1            RFACTs (0=left, 1=Crout, 2=Right)\n1            # of broadcast\n1            BCASTs (0=1rg,1=1rM,2=2rg,3=2rM,4=Lng,5=LnM)\n1            # of lookahead depth\n1            DEPTHs (>=0)\n2            SWAP (0=bin-exch,1=long,2=mix)\n64           swapping threshold\n0            L1 in (0=transposed,1=no-transposed) form\n0            U  in (0=transposed,1=no-transposed) form\n1            Equilibration (0=no,1=yes)\n8            memory alignment in double (> 0)\n" > "$AT/HPL.dat"
( cd "$AT" && mpirun -np 2 "$INSTALL/xhpl" > autotest.out 2>&1 ) \
  || { echo "!! autotest falló (conservado en autotest.out)"; exit 5; }
grep -q "PASSED" "$AT/autotest.out" || { echo "!! autotest sin PASSED (conservado)" >&2; exit 5; }

echo "== compile_hpl $STACK OK: $INSTALL/xhpl (autotest PASSED) $(date -Is)"
