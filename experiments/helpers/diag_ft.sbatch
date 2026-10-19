#!/usr/bin/env bash
#SBATCH --job-name=diag-ft
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --account=<account>
#SBATCH --time=00:20:00
#SBATCH --output=data/raw/phaseB/diag-ft-%j.out

# Diagnóstico acotado del UNSUCCESSFUL de FT clase D en la pila gcc a 128 ranks
# (humo 83242). Uso (el orquestador encadena las fases en serie dentro de cpu112c):
#   diag_ft.sbatch rebuild      -> recompila ft.D.x por pila con el make.def de
#                                  fase B (-O3 -march=sapphirerapids; el actual es
#                                  del 30-sep con -march=native) y guarda el
#                                  anterior como ft.D.x.native-30sep
#   diag_ft.sbatch sweep <nodos>  -> FT D con el binario nuevo, AMBAS pilas:
#                                  1 nodo: 64r y 128r (sobrescrito)
#                                  2 nodos: 128r | 4 nodos: 256r | 8 nodos: 512r
# Criterio: Verification = SUCCESSFUL / UNSUCCESSFUL. ~10 runs cortos en total.
set -u
source clusters/local.env
SCRATCH="$TURGALIUM_SCRATCH"
W="$PWD/instrumentation/cmdlog.sh"
export CMDLOG_DIR="$SCRATCH/cc/raw/phaseB/diag-ft-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="diag-ft-$SLURM_JOB_ID"
MARCH=sapphirerapids
DESTARCH=spr   # convención de fase B: benchmarks/npb/<pila>/spr/
NPB_SRC="$SCRATCH/src/NPB3.4.1/NPB3.4-MPI"
MODE="${1:?uso: sbatch ... diag_ft.sbatch <rebuild|sweep> [nodos]}"
mkdir -p "$CMDLOG_DIR"
echo "== diag FT ($MODE ${2:-}) (job $SLURM_JOB_ID) en $(hostname -s)"

ft_env() {  # $1 = pila; $2 = ranks totales; $3 = ranks por package (gcc)
  module purge 2>/dev/null || true
  local rpn=$(( $2 / ${SLURM_JOB_NUM_NODES:-1} ))   # ranks por nodo
  case "$1" in
    gcc)   module load openmpi_gcc/5.0.5 ucx/1.9.0
           export OMPI_MCA_pml=ucx UCX_TLS="rc,sm,self" UCX_LOG_LEVEL=info
           LAUNCH=(mpirun -np "$2" --map-by ppr:$3:package --bind-to core --oversubscribe) ;;
    intel) module load intel/2025.3.2
           export I_MPI_FABRICS=ofi FI_PROVIDER=mlx I_MPI_DEBUG=5
           if [ "$rpn" -eq 64 ]; then export I_MPI_PIN_PROCESSOR_LIST="0-31,56-87"
           elif [ "$rpn" -lt 64 ]; then export I_MPI_PIN_PROCESSOR_LIST="$(seq -s, 0 $(( rpn - 1 )))"
           fi
           # rpn > 64 (1n-128r sobrescrito): pinning por defecto de Intel MPI
           LAUNCH=(mpirun -n "$2" -ppn "$rpn") ;;
  esac
}

ft_run() {  # $1 = pila; $2 = ranks totales; $3 = ranks por package (gcc); $4 = etiqueta
  local pila="$1" total="$2" rpp="$3" label="$4"
  ft_env "$pila" "$total" "$rpp"
  local log="$CMDLOG_DIR/ft-$pila-$label.log"
  bash "$W" "${LAUNCH[@]}" "$SCRATCH/benchmarks/npb/$pila/$DESTARCH/ft.D.x" > "$log" 2>&1
  local res="SIN-VERIFICACION"
  grep -q "Verification *= *SUCCESSFUL" "$log" && res="SUCCESSFUL"
  grep -q "Verification *= *UNSUCCESSFUL" "$log" && res="UNSUCCESSFUL"
  echo "  FT D $pila $label: $res"
}

if [ "$MODE" = rebuild ]; then
  rebuild_ft() {  # $1 = pila; $2 = módulos
    local name="$1"
    echo "== recompilación FT $name ($MARCH)"
    module purge 2>/dev/null || true; module load $2
    local fc; fc="$(command -v mpif90 || command -v mpifort)"
    local d="$SCRATCH/src/phaseB/npb-$name-$MARCH"
    [ -d "$d" ] || cp -r "$NPB_SRC" "$d"
    cd "$d"
    cat > config/make.def <<EOF
CC = mpicc -march=$MARCH
MPICC = mpicc -march=$MARCH
FC = $fc -march=$MARCH
MPIFC = $fc -march=$MARCH
FLINK = \$(FC)
CCFLAGS = -O3
FFLAGS = -O3 -march=$MARCH -fallow-argument-mismatch -fallow-invalid-boz
FLINKFLAGS =
RAND = randi8
RANDPAR = randi8
BINDIR = ../bin
WTIME = wtime_ompi.c
EOF
    mkdir -p bin
    bash "$W" make ft CLASS=D 2>&1 | tail -1
    local dest="$SCRATCH/benchmarks/npb/$name/$DESTARCH"
    if [ -f bin/ft.D.x ]; then
      [ -f "$dest/ft.D.x" ] && [ ! -f "$dest/ft.D.x.native-30sep" ] && cp "$dest/ft.D.x" "$dest/ft.D.x.native-30sep"
      cp bin/ft.D.x "$dest/ft.D.x" && echo "   ok ft.D.x ($name, recompilado)"
    else
      echo "   !! ft.D.x no generado ($name)"
    fi
    cd "$SCRATCH/src/phaseB"
  }
  rebuild_ft gcc   "openmpi_gcc/5.0.5 ucx/1.9.0"
  rebuild_ft intel "intel/2025.3.2"
  echo "== fin rebuild FT (job $SLURM_JOB_ID)"
  exit 0
fi

# sweep: $2 = nº de nodos (1, 2, 4 u 8)
N="${2:?falta el número de nodos}"
case "$N" in
  1) R=64;  echo "-- 1 nodo: 64r y 128r sobrescrito (ambas pilas)"
     ft_run gcc 64 32  "1n-64r";   ft_run gcc 128 64 "1n-128r-sobrescrito"
     ft_run intel 64 32 "1n-64r";  ft_run intel 128 64 "1n-128r-sobrescrito" ;;
  2) R=128; echo "-- 2 nodos: 128r (64/nodo, ambas pilas)"
     ft_run gcc 128 32 "2n-128r";  ft_run intel 128 32 "2n-128r" ;;
  4) R=256; echo "-- 4 nodos: 256r (64/nodo)"
     ft_run gcc 256 32 "4n-256r";  ft_run intel 256 32 "4n-256r" ;;
  8) R=512; echo "-- 8 nodos: 512r (64/nodo)"
     ft_run gcc 512 32 "8n-512r";  ft_run intel 512 32 "8n-512r" ;;
  *) echo "nodos no soportados: $N" >&2; exit 2 ;;
esac
echo "== fin sweep FT $N nodos (job $SLURM_JOB_ID); registro en $CMDLOG_DIR"
