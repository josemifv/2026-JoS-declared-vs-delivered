#!/usr/bin/env bash
# Pares intra-switch que FALTAN en la prueba de equivalencia (auditoría 2026-10-05,
# punto 4): b9p05, 06, 07, 08 y 10 no tienen par OSU; aac120 y acc120 solo tienen el
# par cruzado. Compara contra el nodo fijo de referencia (b9p01, como los pares
# [01,X] originales); todos los b9p son del mismo grupo de switch (sw3) y los pares
# aac/acc son intra sw1/sw2 (switch_groups.json). [PROPUESTO POR EL AGENTE, pendiente
# de aprobación; NO lanza nada con DRY_RUN=1 (por defecto): solo imprime las líneas.]
#
# Uso: bash experiments/equiv_pares_faltantes.sh        # DRY_RUN: muestra las líneas
#      DRY_RUN=0 bash experiments/equiv_pares_faltantes.sh   # lanza los 14 jobs
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env

TPL=experiments/equivalencia.sh
REPO=<home>
OSU_DIR="$TURGALIUM_SCRATCH/benchmarks/osu/libexec/osu-micro-benchmarks/mpi/pt2pt"
STREAM_BIN="$TURGALIUM_SCRATCH/src/stream/stream_c"   # el mismo que usó la prueba (82373)

[ -x "$STREAM_BIN" ] || { echo "!! falta $STREAM_BIN" >&2; exit 3; }
[ -f "$TPL" ] || { echo "!! falta plantilla $TPL" >&2; exit 3; }

PAIRS=(
  "cpu112c b9p01,b9p05 2 112"
  "cpu112c b9p01,b9p06 2 112"
  "cpu112c b9p01,b9p07 2 112"
  "cpu112c b9p01,b9p08 2 112"
  "cpu112c b9p01,b9p10 2 112"
  "cpu36c  aac102,aac120 2 36"
  "cpu36c  acc101,acc120 2 36"
)

TMPDIR_JOBS="$(mktemp -d /tmp/equiv-pares-XXXXXX)"
trap 'rm -rf "$TMPDIR_JOBS"' EXIT

N=0
for p in "${PAIRS[@]}"; do
  read -r PART NL NODES NCPUS <<< "$p"
  for PRUEBA in lat bw; do
    JF="$TMPDIR_JOBS/equiv-${PRUEBA}-$(echo "$NL" | tr ',' '_').sbatch"
    sed -e "s|<<<PARTITION>>>|$PART|"  -e "s|<<<NODELIST>>>|$NL|" \
        -e "s|<<<NNODES>>>|$NODES|"    -e "s|<<<SCRATCH>>>|$TURGALIUM_SCRATCH|" \
        -e "s|<<<REPO>>>|$REPO|"       -e "s|<<<STREAM_BIN>>>|$STREAM_BIN|" \
        -e "s|<<<OSU_DIR>>>|$OSU_DIR|" -e "s|<<<NCPUS>>>|$NCPUS|" \
        -e "s|<<<PRUEBA>>>|$PRUEBA|" "$TPL" > "$JF"
    bash -n "$JF"
    if [ "${DRY_RUN:-1}" = 1 ]; then
      echo "DRY_RUN: sbatch -p $PART --nodelist=$NL --nodes=$NODES # prueba=$PRUEBA cpus=$NCPUS"
    else
      sbatch "$JF"
    fi
    N=$((N + 1))
  done
done
echo "== $N jobs de equivalencia (DRY_RUN=${DRY_RUN:-1}: 1 solo muestra las líneas; 0 lanza)"
