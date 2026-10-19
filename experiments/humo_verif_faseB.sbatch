#!/usr/bin/env bash
#SBATCH --job-name=humo-verifB
#SBATCH --nodes=2
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --account=<account>
#SBATCH --time=01:00:00
#SBATCH --output=data/raw/phaseB/humo-verifB-%j.out

# Verificación funcional (DEVIATIONS 2026-10-03; AGENTS.md §0b) de los binarios
# de la fase B, con cada uno de los 4 pares seleccionados por R2:
#   1) transporte efectivo cargado (UCX_LOG_LEVEL=info / I_MPI_DEBUG=5),
#   2) mapa pedido = real (R10),
#   3) librerías cargadas por el proceso (ldd + /proc/<pid>/maps de un rank vivo).
#
# CRITERIO DE "OK" (fijado a priori, 2026-10-04):
#   - NPB (EP, FT, CG, MG clase D): la salida contiene "Verification Successful"
#     y NO contiene "Verification failed". (Nota: NPB 3.4.1 imprime
#     "Verification Successful", no "Verification = SUCCESSFUL".)
#   - HPCG 3.1.0: la salida contiene "HPCG result is VALID".
# NO lanza ninguna ronda de fase B.
set -u
source clusters/local.env
REPO="$PWD"
SCRATCH="$TURGALIUM_SCRATCH"
W="$REPO/instrumentation/cmdlog.sh"     # ruta ABSOLUTA: el script hace cd
export CMDLOG_DIR="$SCRATCH/cc/raw/phaseB/humo-verif-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="humo-verifB-$SLURM_JOB_ID"
export LEVEL1_MODE=unprivileged
NPB="$SCRATCH/benchmarks/npb"; HPCG="$SCRATCH/benchmarks/phaseB/hpcg"
MAPCHECK='echo "$(hostname -s) rank=${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-${SLURM_PROCID:-NA}}} cpus=$(taskset -pc $$ | awk "{print \$NF}")"'
mkdir -p "$CMDLOG_DIR" data/raw/phaseB
NODOS=$(srun --ntasks=2 --ntasks-per-node=1 hostname -s | tr '\n' ' ')
echo "== humo verif fase B (job $SLURM_JOB_ID) en $NODOS"
echo "== criterio: NPB 'Verification Successful' (sin 'Verification failed'); HPCG 'HPCG result is VALID'"

env_par() {  # $1 = pila; $2 = transporte
  module purge 2>/dev/null || true
  case "$1" in
    gcc) module load openmpi_gcc/5.0.5 ucx/1.9.0
         export OMPI_MCA_pml=ucx UCX_TLS="${2},sm,self" UCX_LOG_LEVEL=info
         unset I_MPI_FABRICS FI_PROVIDER FI_TCP_IFACE I_MPI_DEBUG I_MPI_PMI_LIBRARY I_MPI_PIN_PROCESSOR_LIST ;;
    intel) module load intel/2025.3.2
         export I_MPI_FABRICS=ofi FI_PROVIDER="$2" I_MPI_DEBUG=5
         unset OMPI_MCA_pml UCX_TLS UCX_LOG_LEVEL ;;
  esac
}
launch() {  # $1 = pila; $2 = ntasks; $3 = ppn
  case "$1" in
    gcc)   LAUNCH=(mpirun -np "$2" --map-by ppr:32:package --bind-to core) ;;
    intel) if [ "$3" = 64 ]; then export I_MPI_PIN_PROCESSOR_LIST="0-31,56-87"
           else export I_MPI_PIN_PROCESSOR_LIST="$(seq -s, 0 $(( $3 - 1 )))"; fi
           LAUNCH=(mpirun -n "$2" -ppn "$3") ;;
  esac
}
# NPB 3.4.1 imprime "Verification    =               SUCCESSFUL" (o "failed")
npb_ok()  { grep -Eq "Verification *= *SUCCESSFUL" "$1" && ! grep -Eq "Verification *= *FAILED|Verification failed" "$1"; }
# HPCG: valido si stdout o alguno de sus YAML contiene "HPCG result is VALID"
hpcg_ok() { local d; d=$(dirname "$1"); grep -q "HPCG result is VALID" "$1" && return 0
            grep -q "HPCG result is VALID" "$d"/HPCG-Benchmark_*.txt 2>/dev/null; }

NPB_OK=0; NPB_TOT=0; HPCG_OK=0; HPCG_TOT=0; MAPFALLO=0
for par in "gcc rc" "gcc dc" "gcc ud" "intel mlx"; do
  set -- $par; PILA="$1"; TRANS="$2"
  echo "================= par $PILA/$TRANS"
  env_par "$PILA" "$TRANS"
  launch "$PILA" 128 64
  echo "--- librerías del binario EP bajo el stack ($PILA):"
  ldd "$NPB/$PILA/spr/ep.D.x" 2>&1 | grep -E "libmpi|libucp|libucs|libuct|libfabric|libgfortran" | awk '{print "    "$1}'
  echo "--- mapa pedido = real (R10):"
  if "${LAUNCH[@]}" bash -c "$MAPCHECK" > "$CMDLOG_DIR/map-$PILA-$TRANS.txt" 2>&1; then
    echo "    ranks=$(grep -c 'cpus=' "$CMDLOG_DIR/map-$PILA-$TRANS.txt")  cpus distintos=$(awk '{print $NF}' "$CMDLOG_DIR/map-$PILA-$TRANS.txt" | sort -u | wc -l)"
  else
    echo "    !! map-check FALLO"; MAPFALLO=$((MAPFALLO+1))
  fi
  # captura de /proc/<pid>/maps de un rank vivo (librerías cargadas por el proceso)
  ( for i in $(seq 1 40); do
      p=""; for c in $(pgrep -f "ft.D.x" || true); do
        [ "$(basename "$(readlink /proc/$c/exe 2>/dev/null)" 2>/dev/null)" = "ft.D.x" ] && { p=$c; break; }
      done
      if [ -n "$p" ]; then
        grep -E "libmpi|libucp|libucs|libuct|libfabric|libmlx|libgfortran" /proc/$p/maps 2>/dev/null \
          | awk '{print "    PROC "$NF}' | sort -u
        break
      fi
      sleep 1
    done ) &
  # kernels NPB clase D (FT sirve además para el transporte efectivo y los maps)
  for k in ep ft cg mg; do
    log="$CMDLOG_DIR/${k}-$PILA-$TRANS.log"
    bash "$W" "${LAUNCH[@]}" "$NPB/$PILA/spr/$k.D.x" > "$log" 2>&1
    NPB_TOT=$((NPB_TOT+1))
    if npb_ok "$log"; then NPB_OK=$((NPB_OK+1)); res="OK"; else res="FALLO"; fi
    echo "    NPB $k clase D: $res  ($(grep -m1 'Verification Successful\|Verification failed' "$log" | tr -s ' ' | sed 's/^ //'))"
    if [ "$k" = ft ]; then
      wait
      echo "    transporte efectivo:"
      grep -a -m2 -E "inter-node cfg#[0-9]+ tag|libfabric provider" "$log" | sed 's/^/      /' | cut -c1-140
    fi
  done
  # HPCG 3.1.0 con problema mínimo (1 nodo, 8 ranks) y criterio de validez.
  # IMPORTANTE: ppr:32:package con np<64 no lanza nada en OMPI 5 (fallo PMIx
  # silencioso, rc=0): el mapa para 8 ranks usa ppr:8:package / -ppn 8.
  mkdir -p "$CMDLOG_DIR/hpcg-$PILA-$TRANS"
  cp "$CMDLOG_DIR/hpcg.dat" "$CMDLOG_DIR/hpcg-$PILA-$TRANS/" 2>/dev/null || \
    printf "HPCG benchmark input file\nSandia National Laboratories; University of Tennessee, Knoxville\n32 32 32\n10\n" > "$CMDLOG_DIR/hpcg-$PILA-$TRANS/hpcg.dat"
  logh="$CMDLOG_DIR/hpcg-$PILA-$TRANS/run.log"
  ( cd "$CMDLOG_DIR/hpcg-$PILA-$TRANS" && \
    if [ "$PILA" = gcc ]; then mpirun -np 8 --map-by ppr:8:package --bind-to core "$HPCG/$PILA/xhpcg" > run.log 2>&1
    else I_MPI_PIN_PROCESSOR_LIST=0,1,2,3,4,5,6,7 mpirun -n 8 -ppn 8 "$HPCG/$PILA/xhpcg" > run.log 2>&1; fi )
  HPCG_TOT=$((HPCG_TOT+1))
  if hpcg_ok "$logh"; then HPCG_OK=$((HPCG_OK+1)); echo "    HPCG 3.1.0: OK  ($(grep -m1 'HPCG result is' "$logh" "$CMDLOG_DIR/hpcg-$PILA-$TRANS"/HPCG-Benchmark_*.txt 2>/dev/null | tr -s ' ' | cut -c1-90))"
  else echo "    HPCG 3.1.0: FALLO"; fi
done
echo "================= RESUMEN"
echo "  NPB  clase D: $NPB_OK/$NPB_TOT verificaciones OK"
echo "  HPCG 3.1.0  : $HPCG_OK/$HPCG_TOT con resultado VALID"
echo "  map-checks fallidos: $MAPFALLO"
echo "== humo de verificación terminado (job $SLURM_JOB_ID); registro en $CMDLOG_DIR"
