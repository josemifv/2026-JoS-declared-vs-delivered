#!/usr/bin/env bash
# Ligero GPU (R14): BabelStream compilado desde fuente (no hay módulo del clúster).
# Una compilación por ARQUITECTURA (DEVIATIONS 2026-10-04): sm_70 (volta) o sm_90
# (h100); el binario queda en scratch compartido y sirve para todos los nodos de la
# partición. NO se construye ni instala ningún stack MPI para GPU (el ligero GPU no
# tiene OSU device-to-device: openmpi_gcc/5.0.5_cuda12 sin soporte CUDA, job 83302).
#
# Compilación DIRECTA con nvcc, sin cmake: el modulefile cmake/3.18.2 está ROTO
# (declara load("gcc/7.5.0") — módulo inexistente — y su payload /opt/cmake/3.18.2/bin
# tampoco existe; jobs 83357/83372, DEVIATIONS 2026-10-04) y no hay cmake en ninguna
# ruta del clúster. El build oficial de BabelStream 5.0 para el modelo CUDA equivale a
# compilar main.cpp + cuda/CUDAStream.cu con -DCUDA (main.cpp selecciona el modelo por
# preprocesador; CMakeLists no añade flags extra al modelo CUDA).
#
# Uso: sbatch --partition=volta --gres=gpu:1 --nodelist=aap01 --time=00:30:00 \
#            experiments/helpers/compile_babelstream.sbatch sm70
#      sbatch --partition=h100  --gres=gpu:1 --nodelist=b9p17 --time=00:30:00 \
#            experiments/helpers/compile_babelstream.sbatch sm90
# (la partición exige --gres incluso para compilar: DEVIATIONS 2026-09-26; el
# autotest --list corre sobre la GPU de la propia asignación y valida la arquitectura)
#SBATCH --job-name=cc-compile-bs
#SBATCH --exclusive
#SBATCH --gres=gpu:1
#SBATCH --output=data/raw/ligero/%x-%j.out
#SBATCH --time=00:30:00

set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env

ARCH="${1:?uso: compile_babelstream.sbatch <sm70|sm90>}"
case "$ARCH" in
  sm70) CARCH=sm_70 ;; sm90) CARCH=sm_90 ;;
  *) echo "!! arquitectura desconocida: $ARCH (sm70|sm90)" >&2; exit 2 ;;
esac

SCRIPT_SHA="$(sha256sum "$(readlink -f "$0")" | awk '{print $1}')"
echo "== compile_babelstream $ARCH job=$SLURM_JOB_ID nodo=$(hostname -s) sha256=$SCRIPT_SHA $(date -Is)"

# El compilador anfitrión es el g++ del sistema (11.5), visible para nvcc vía PATH;
# nvcc 12.9 lo admite (el gcc 7.5 que pedía el modulefile roto, no).
module purge 2>/dev/null || true
module load cuda/12.9.1
command -v nvcc >/dev/null || { echo "!! nvcc no disponible" >&2; exit 3; }
nvcc --version | tail -1

SRC="$TURGALIUM_SCRATCH/src/BabelStream-5.0"
[ -d "$SRC" ] || { tar xzf "$TURGALIUM_SCRATCH/src/babelstream.tar.gz" -C "$TURGALIUM_SCRATCH/src"; }
[ -f "$SRC/src/main.cpp" ] && [ -f "$SRC/src/cuda/CUDAStream.cu" ] \
    || { echo "!! fuente no disponible en $SRC" >&2; exit 3; }

BIN="$TURGALIUM_SCRATCH/benchmarks/babelstream/$ARCH/babelstream"
mkdir -p "$(dirname "$BIN")"
nvcc -O3 -Xcompiler -O3 -std=c++11 -arch="$CARCH" -DCUDA \
     -I "$SRC/src" -I "$SRC/src/cuda" \
     "$SRC/src/main.cpp" "$SRC/src/cuda/CUDAStream.cu" \
     -o "$BIN"

# Autotest en la GPU de la asignación: valida que el binario corre en ESTA
# arquitectura (si el arch no corresponde, falla aquí y no en los nodos de medida)
"$BIN" --list
echo "== instalado: $BIN sha256=$(sha256sum "$BIN" | awk '{print $1}')"
