#!/usr/bin/env bash
# Derivado de ed_ft.sbatch; original intacto.
# Orden informes/ordenes/2026-10-14-T19-ed-cpu36c.md y DEVIATIONS 2026-10-14 T19.
# FT D, cpu36c, 8x32=256 ranks, CLX. R1: r1 calentamiento, r2-11 efectivas.
# Ingenuo: GCC/Open MPI por defecto, sin opciones de mapping/binding.
# Recomendado: intelc/mlx, CPUs 0-15,18-33; exclusiones en el lanzador L14.
# D-B recomendado: allreduce GCC/default 64 KiB antes/después, como L3-v3.
# Nivel 1 unprivileged por asignación (como ed_ft.sbatch); todo bajo CMDLOG_DIR.
# Map-check por run con el MISMO LAUNCH; el mapa ingenuo se observa, no se impone.
# Cualquier fallo de QA, FT o D-B hace fallar el job: puerta afterok de los humos.
# Uso exclusivo desde el lanzador firmado: <ingenuo|recomendado> <r_from> <r_to>.
#SBATCH --job-name=cc-ed36-ft
#SBATCH --exclusive
#SBATCH --partition=cpu36c
#SBATCH --nodes=8
#SBATCH --ntasks=256
#SBATCH --ntasks-per-node=32
#SBATCH --output=data/raw/infrautil/%x-%j.out
#SBATCH --time=00:20:00

set -euo pipefail
cd "${SLURM_SUBMIT_DIR:?falta SLURM_SUBMIT_DIR}"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
: "${TURGALIUM_REPO:?}" "${TURGALIUM_SCRATCH:?}"
export LC_ALL=C
MODE="${1:?modo}"; R_FROM="${2:?r_from}"; R_TO="${3:?r_to}"
[[ "$R_FROM" =~ ^([1-9]|10|11)$ && "$R_TO" =~ ^([1-9]|10|11)$ ]] \
  && [ "$R_FROM" -le "$R_TO" ] || { echo "!! rondas fuera de 1..11" >&2; exit 2; }
[ "${SLURM_JOB_NUM_NODES:?}" = 8 ] && [ "${SLURM_NTASKS:?}" = 256 ] \
  || { echo "!! E-d requiere 8 nodos y 256 ranks" >&2; exit 3; }
NPN=32; NT=256
REPO_COMMIT="$(cat .deploy-commit)"
[[ "$REPO_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "!! .deploy-commit inválido"; exit 3; }
SCRIPT_SHA="$(sha256sum "$(readlink -f "$0")" | awk '{print $1}')"
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/infrautil/ed36-$MODE-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="ed36-$MODE-$SLURM_JOB_ID"
export LEVEL1_RUN_ID="$CMDLOG_RUN_ID" LEVEL1_MODE=unprivileged LEVEL1_CLUSTER=turgalium
export CONTEXT_DIR="$CMDLOG_DIR/context" LEVEL1_STATE_DIR="$CMDLOG_DIR/level1_state"
CMDLOG="$TURGALIUM_REPO/instrumentation/cmdlog.sh"
L1="$TURGALIUM_REPO/instrumentation/level1_capture.sh"
[ -x "$CMDLOG" ] && [ -f "$L1" ] || { echo "!! falta instrumentación"; exit 3; }
mkdir -p "$CMDLOG_DIR"
FAILED=0
fail() { echo "!! FALLO: $*" >&2; FAILED=1; }

# Quitar overrides heredados; los módulos aportan su entorno normal.
while IFS='=' read -r key _; do
  case "$key" in UCX_*|OMPI_MCA_*|PRTE_MCA_*|I_MPI_*|FI_PROVIDER|FI_LOG_LEVEL) unset "$key" ;; esac
done < <(env)
module purge
case "$MODE" in
  ingenuo)
    module load openmpi_gcc/5.0.5 ucx/1.9.0
    PAIR_LABEL=gcc/default
    BIN="$TURGALIUM_SCRATCH/benchmarks/npb/gcc/clx/ft.D.x"
    LAUNCH=(mpirun -np "$NT")
    echo "Transporte ingenuo: selección por defecto; no se exige un proveedor concreto."
    ;;
  recomendado)
    module load intel/2025.3.2
    PAIR_LABEL=intelc/mlx
    BIN="$TURGALIUM_SCRATCH/benchmarks/npb/intelc/clx/ft.D.x"
    export I_MPI_FABRICS=ofi FI_PROVIDER=mlx I_MPI_DEBUG=5
    export I_MPI_PIN=1 I_MPI_PIN_PROCESSOR_LIST="0-15,18-33"
    LAUNCH=(mpirun -n "$NT" -ppn "$NPN")
    ;;
  *) echo "!! modo desconocido: $MODE" >&2; exit 2 ;;
esac
[ -x "$BIN" ] || { echo "!! falta binario $BIN"; exit 3; }
MPI_PREFIX="$(dirname "$(dirname "$(readlink -f "$(command -v mpirun)")")")"
echo "== E-d cpu36c job=$SLURM_JOB_ID modo=$MODE rondas=$R_FROM..$R_TO commit=$REPO_COMMIT sha256=$SCRIPT_SHA $(date -Is)"
bash "$CMDLOG" srun --ntasks=8 --ntasks-per-node=1 bash -c \
  'printf "%s SMT=%s\n" "$(hostname -s)" "$(LC_ALL=C lscpu | awk "/Thread\(s\) per core/ {print \$4}")"' \
  > "$CMDLOG_DIR/nodos-smt.txt" 2>&1 || fail "captura nodos/SMT"
awk '/^[^[:space:]]+ SMT=[12]$/ {if (seen[$1]++) bad=1; n++}
     END {exit (bad || n!=8)}' "$CMDLOG_DIR/nodos-smt.txt" || fail "ocho nodos/SMT"
if [ "$MODE" = recomendado ] && grep -qE '^(aac108|aac111|acc111) ' "$CMDLOG_DIR/nodos-smt.txt"; then
  fail "nodo excluido en recomendado"
fi

# ldd del binario en CADA nodo: libmpi debe quedar bajo el prefijo del mpirun.
# No se presupone que el ejecutable mpirun esté enlazado con libmpi (Hydra es shell).
bash "$CMDLOG" srun --ntasks=8 --ntasks-per-node=1 bash -c '
  set -euo pipefail
  echo "== $(hostname -s) ldd $1 mpirun-prefix=$2"
  libs="$(ldd "$1")"; printf "%s\n" "$libs"
  if grep -q "not found" <<< "$libs"; then exit 1; fi
  mpi="$(awk "/libmpi[.]so[^ ]* => / {print \$3}" <<< "$libs")"
  [ -n "$mpi" ] && [[ "$(readlink -f "$mpi")" = "$2/"* ]]
' _ "$BIN" "$MPI_PREFIX" > "$CMDLOG_DIR/ldd-$MODE.txt" 2>&1 || fail "ldd/runtime MPI"

map_ok() {
  awk -v mode="$MODE" '
    FNR==NR {if ($2 ~ /^SMT=/) allowed[$1]=1; next}
    $1=="MAP" {
      if (NF!=5 || !allowed[$2] || $3 !~ /^[0-9]+$/ || $3<0 || $3>=256 ||
          $4 !~ /^[0-9]+$/ || $4<0 || $4>=32 || $5 !~ /^[0-9][0-9,-]*$/) bad=1
      if (ranks[$3]++ || localrank[$2 SUBSEP $4]++) bad=1
      if (mode=="recomendado" && $5!=($4<16 ? $4 : $4+2)) bad=1
      nodes[$2]++; n++
    }
    END {
      for (h in allowed) {hosts++; if (nodes[h]!=32) bad=1}
      exit (bad || n!=256 || hosts!=8)
    }' "$CMDLOG_DIR/nodos-smt.txt" "$1"
}
verify_ft() {
  [ "$1" -eq 0 ] \
    && grep -qE '^[[:space:]]*Verification[[:space:]]*=[[:space:]]*SUCCESSFUL[[:space:]]*$' "$2" \
    && grep -qE '^[[:space:]]*Class[[:space:]]*=[[:space:]]*D[[:space:]]*$' "$2" \
    && grep -q 'Size.*2048x1024x1024' "$2" \
    && grep -qE 'Total processes[[:space:]]*=[[:space:]]*256[[:space:]]*$' "$2"
}
MAPCHECK='set -euo pipefail
printf "MAP %s %s %s %s\n" "$(hostname -s)" \
  "${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-NA}}" \
  "${OMPI_COMM_WORLD_LOCAL_RANK:-${MPI_LOCALRANKID:-NA}}" \
  "$(taskset -pc $$ | awk "{print \$NF}")"'

control_cell() { # subshell: no contamina el entorno intelc de la medida
  [ "$MODE" = recomendado ] || return 0
  local ec v log="$CMDLOG_DIR/control-$1.log"
  if (
    module purge && module load openmpi_gcc/5.0.5 ucx/1.9.0 || exit 1
    unset OMPI_MCA_pml UCX_TLS UCX_LOG_LEVEL I_MPI_FABRICS FI_PROVIDER I_MPI_DEBUG I_MPI_PIN I_MPI_PIN_PROCESSOR_LIST
    bash "$CMDLOG" mpirun -np "$NT" --map-by ppr:16:package --bind-to core \
      "$TURGALIUM_SCRATCH/benchmarks/osu/gcc/clx/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce" -m 65536
  ) > "$log" 2>&1; then ec=0; else ec=$?; fi
  v=SUCCESSFUL
  if [ "$ec" -ne 0 ] || ! awk '$1==65536 && $2 ~ /^[0-9]+([.][0-9]+)?$/ {ok=1} END {exit !ok}' "$log"; then
    v=FALLO; fail "control D-B $1"
  fi
  echo "$SLURM_JOB_ID,$MODE,0,control-$1,gcc/default,$NT,$ec,$v,$log" >> "$MANIFEST"
}

MANIFEST="$CMDLOG_DIR/manifest.csv"
echo "job,modo,ronda,celda,par,ranks,exit_code,verificacion,runlog" > "$MANIFEST"
# Aun si una comprobación posterior aborta, cerrar el muestreador y preservar L1.
finish() { local rc=$?; bash "$L1" stop || rc=1; exit "$rc"; }
trap finish EXIT
bash "$L1" start
bash "$L1" pre
control_cell inicio
for r in $(seq "$R_FROM" "$R_TO"); do
  RD="$CMDLOG_DIR/r$r"; mkdir -p "$RD"
  v=SUCCESSFUL
  if ! bash "$CMDLOG" "${LAUNCH[@]}" bash -c "$MAPCHECK" > "$RD/mapcheck.txt" 2>&1; then
    v=FALLO; fail "map-check exit ronda $r"
  fi
  if ! map_ok "$RD/mapcheck.txt"; then v=FALLO; fail "mapa/ranks/nodos ronda $r"; fi
  if bash "$CMDLOG" "${LAUNCH[@]}" "$BIN" > "$RD/run.log" 2>&1; then ec=0; else ec=$?; fi
  if ! verify_ft "$ec" "$RD/run.log"; then v=FALLO; fail "FT exit/verificación/clase/ranks ronda $r"; fi
  if [ "$MODE" = recomendado ]; then
    if ! grep -qE 'libfabric provider:[[:space:]]*mlx([[:space:]]|$)' "$RD/run.log"; then
      v=FALLO; fail "transporte observado ronda $r"
    fi
    # Verificar además el mapa del PROPIO FT (tabla I_MPI_DEBUG=5).
    awk '$2=="MPI" && $3=="startup():" && $4 ~ /^[0-9]+$/ && $7 ~ /^\{[0-9]+\}$/ {
      cpu=$7; gsub(/[{}]/,"",cpu); print "MAP", $6, $4, $4%32, cpu
    }' "$RD/run.log" > "$RD/ft-map.txt"
    if ! map_ok "$RD/ft-map.txt"; then v=FALLO; fail "mapa efectivo FT ronda $r"; fi
  fi
  # QA c contra la salida que ACABA de producir este job, también en el humo.
  sed 's/SUCCESSFUL/UNSUCCESSFUL/g' "$RD/run.log" > "$RD/qa-negativo.log"
  if verify_ft 0 "$RD/qa-negativo.log" || verify_ft 7 "$RD/run.log"; then
    v=FALLO; fail "autocomprobación negativa QA c"
  fi
  echo "$SLURM_JOB_ID,$MODE,$r,ft-8n,$PAIR_LABEL,$NT,$ec,$v,$RD/run.log" >> "$MANIFEST"
  echo "== ronda=$r exit=$ec verificacion=$v $(date -Is)"
done
control_cell fin
bash "$L1" post
echo "== terminado: fallo=$FAILED manifiesto=$MANIFEST $(date -Is)"
exit "$FAILED"
