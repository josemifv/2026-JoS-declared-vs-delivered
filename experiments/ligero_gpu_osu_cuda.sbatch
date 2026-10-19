#!/usr/bin/env bash
#SBATCH --job-name=cc-osu-cuda
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --partition=volta
#SBATCH --gres=gpu:4
#SBATCH --account=<account>
#SBATCH --output=data/raw/ligero/%x-%j.out
#SBATCH --time=00:30:00
# Prueba funcional de MPI CUDA-aware (D5, DEVIATIONS 2026-10-06): ANTES de omitir
# OSU device-to-device en GPU, se comprueba con un build propio.
#   1) Compila OSU con CUDA contra openmpi_gcc/5.0.5_cuda12 + cuda/12.9.1
#      (--enable-cuda=basic --with-cuda=<CUDA del módulo>; árbol limpio osu-cuda).
#      v2 (Prompt C 5.2): se VERIFICA en config.log que CUDA quedó activado
#      (invocación con --enable-cuda + ac_cv_header_cuda_h=yes); si no, la prueba
#      NO ES VÁLIDA y no se concluye nada sobre el MPI (exit 5).
#   2) Controles ANTES de la prueba (v2, Prompt C 5.3):
#      - ompi_info --parsable --all | grep -i cuda (incluye mpi_built_with_cuda_support)
#      - ucx_info -v  y  ucx_info -d | grep -i cuda
#      - osu_bw H H con el mismo mpirun (2 ranks en 1 nodo): si H H falla es un
#        fallo de LANZAMIENTO, no de CUDA → resultado INVALIDA.
#   3) Solo si H H funciona y `osu_bw -d cuda D D` (CUDA_VISIBLE_DEVICES=0,1, un
#      rank por GPU) falla se registra CUDA-NO-FUNCIONAL, guardando el error textual.
# Registra la salida y el ERROR si falla; el exit real del job queda registrado
# (QA d/f). Resultados: (a) INVALIDA → repetir con otro mecanismo de lanzamiento;
# (b) CUDA-NO-FUNCIONAL → discrepancia declarado/real demostrada; (c) funciona →
# se añade OSU GPU por partición (D5). NO es una medida del estudio.
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}" || exit 1
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env

REPO_COMMIT="$(awk '{print $1}' .deploy-commit 2>/dev/null || true)"
echo "$REPO_COMMIT" | grep -qE '^[0-9a-f]{7,40}$' || REPO_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo 'desconocido (clon no alineado)')"
SCRIPT_SHA="$(sha256sum "$(readlink -f "$0")" | awk '{print $1}')"
CMDLOG="$TURGALIUM_REPO/instrumentation/cmdlog.sh"
[ -x "$CMDLOG" ] || { echo "!! falta cmdlog" >&2; exit 3; }
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/ligero/osu-cuda-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="osu-cuda-$SLURM_JOB_ID"
mkdir -p "$CMDLOG_DIR" data/raw/ligero

SRC="$TURGALIUM_SCRATCH/src/osu-micro-benchmarks-7.4"
[ -d "$SRC" ] || { echo "!! fuente OSU no encontrada: $SRC" >&2; exit 1; }

echo "== OSU CUDA job=$SLURM_JOB_ID nodo=$(hostname -s) sha256=$SCRIPT_SHA $(date -Is)"
echo "== commit(desplegado): $REPO_COMMIT"
nvidia-smi -L || true

module purge 2>/dev/null || true
module load cuda/12.9.1 openmpi_gcc/5.0.5_cuda12
CUDA_ROOT="$(dirname "$(dirname "$(command -v nvcc)")")"
echo "== CUDA_ROOT (del módulo, por nvcc): $CUDA_ROOT"
{ echo "## module list"; module list 2>&1 || true
  echo "## ompi_info --parsable --all | grep -i cuda"
  ompi_info --parsable --all 2>/dev/null | grep -i cuda || echo "(sin menciones de cuda en ompi_info)"
  echo "## mpi_built_with_cuda_support:"
  ompi_info --parsable --all 2>/dev/null | grep -i "mpi_built_with_cuda_support" || echo "(parámetro no encontrado)"
  echo "## ucx_info -v"; ucx_info -v 2>&1 | head -5 || true
  echo "## ucx_info -d | grep -i cuda"; ucx_info -d 2>/dev/null | grep -i cuda || echo "(sin instancias cuda en ucx_info -d)"
  echo "## nvcc:"; nvcc --version | tail -1 || true
} > "$CMDLOG_DIR/controles-mpi-ucx.txt" 2>&1 || true
cat "$CMDLOG_DIR/controles-mpi-ucx.txt"

# 1) build limpio con CUDA (--with-cuda: ruta del módulo; Prompt C 5.2)
D="$TURGALIUM_SCRATCH/src/osu-cuda"
[ -d "$D" ] || cp -r "$SRC" "$D"
cd "$D" || exit 3
echo "--- configure --enable-cuda=basic --with-cuda=$CUDA_ROOT"
if ! bash "$CMDLOG" ./configure --prefix="$TURGALIUM_SCRATCH/benchmarks/osu/gcc-cuda" \
        CC=mpicc --enable-cuda=basic --with-cuda="$CUDA_ROOT" \
        > "$CMDLOG_DIR/configure.log" 2>&1; then
  echo "!! CONFIGURE FALLÓ (evidencia en $CMDLOG_DIR/configure.log):"
  tail -20 "$CMDLOG_DIR/configure.log"
  exit 3
fi
# v2 (Prompt C 5.2): CUDA debe quedar ACTIVADO en config.log; si no, la prueba no
# es válida y NO se concluye nada sobre el MPI.
CF="$CMDLOG_DIR/config.log"
cp config.log "$CF"
grep -E -- "--enable-cuda=basic --with-cuda" "$CF" | head -2 || true
if ! grep -q "ac_cv_header_cuda_h=yes" "$CF"; then
  echo "!! CUDA NO QUEDÓ ACTIVADO (config.log sin ac_cv_header_cuda_h=yes):"
  grep -i "cuda" "$CF" | head -10 || true
  echo "== RESULTADO: PRUEBA NO VÁLIDA (build sin CUDA verificado): no se concluye nada sobre el MPI."
  exit 5
fi
echo "--- configure: CUDA ACTIVADO (ac_cv_header_cuda_h=yes en config.log)"
if ! bash "$CMDLOG" make -j 8 > "$CMDLOG_DIR/make.log" 2>&1; then
  echo "!! MAKE FALLÓ (evidencia en $CMDLOG_DIR/make.log):"
  tail -20 "$CMDLOG_DIR/make.log"
  exit 3
fi
make install > "$CMDLOG_DIR/make-install.log" 2>&1
BW="$TURGALIUM_SCRATCH/benchmarks/osu/gcc-cuda/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bw"
[ -x "$BW" ] || { echo "!! osu_bw no generado" >&2; exit 3; }
echo "--- ldd osu_bw (¿enlaza libcuda/cudart?):"
ldd "$BW" | grep -E "cuda|nvidia" || echo "(sin librerías CUDA enlazadas dinámicamente — señal de que el build NO es CUDA-aware)"

# 2) CONTROL de lanzamiento (v2, Prompt C 5.3): osu_bw H H con el MISMO mpirun.
#    -ppn no es opción de Open MPI → --map-by ppr:2:node (Prompt C 5.1).
#    Si H H falla, es un fallo de lanzamiento, NO de CUDA: resultado INVALIDA.
echo "--- control: osu_bw H H (2 ranks en el nodo, mismo mpirun)"
if bash "$CMDLOG" mpirun -np 2 --map-by ppr:2:node "$BW" H H \
    > "$CMDLOG_DIR/osu_bw-HH.log" 2>&1; then
  echo "control H H: OK"
else
  EC_HH=$?
  echo "exit=$EC_HH"
  echo "!! control osu_bw H H FALLÓ (evidencia en $CMDLOG_DIR/osu_bw-HH.log):"
  tail -20 "$CMDLOG_DIR/osu_bw-HH.log"
  echo "== RESULTADO: INVALIDA (fallo de lanzamiento, no de CUDA); no se concluye nada sobre CUDA."
  exit 6
fi

# 3) prueba CUDA device-to-device entre DOS GPU del nodo (un rank por GPU)
export CUDA_VISIBLE_DEVICES="0,1"
echo "--- osu_bw -d cuda D D (CUDA_VISIBLE_DEVICES=0,1; 2 ranks, 1 por GPU)"
if bash "$CMDLOG" mpirun -np 2 --map-by ppr:2:node "$BW" -d cuda D D \
    > "$CMDLOG_DIR/osu_bw-cuda.log" 2>&1; then
  EC=0
else
  EC=$?
fi
echo "exit=$EC"
head -20 "$CMDLOG_DIR/osu_bw-cuda.log"
if [ "$EC" -ne 0 ]; then
  echo "!! osu_bw -d cuda FALLÓ (evidencia conservada en $CMDLOG_DIR/osu_bw-cuda.log):"
  tail -20 "$CMDLOG_DIR/osu_bw-cuda.log"
  echo "== RESULTADO: CUDA-NO-FUNCIONAL (control H H OK, D D falló; error textual arriba)."
  exit 4
fi
echo "== RESULTADO: osu_bw -d cuda FUNCIONA (D5): se añadirá OSU GPU por partición."
