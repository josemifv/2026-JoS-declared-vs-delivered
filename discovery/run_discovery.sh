#!/usr/bin/env bash
#
# run_discovery.sh - lanzador Slurm del descubrimiento (DISCOVERY.md seccion 2).
#
# Genera un job por nodo (--exclusive y --nodelist) que ejecuta
# discovery/collect_node.py en el nodo asignado, y deja los resultados en
# data/raw/discovery/<cluster>/ segun DISCOVERY.md seccion 5. Se puede limitar a
# una lista de nodos concreta con --nodes (utilidad del smoke test).
#
# Uso:
#   discovery/run_discovery.sh --cluster <nombre> [opciones]
#
# Opciones:
#   --cluster NOMBRE     (obligatorio) nombre del cluster.
#   --partition NOMBRE   particion declarada a la que limitar el barrido.
#   --nodes "n1,n2,..."  lista explicita de nodos (omite sinfo).
#   --repo RUTA          copia del repositorio en el cluster (por defecto, este).
#   --data-dir DIR       destino de resultados
#                        (por defecto <repo>/data/raw/discovery/<cluster>).
#   --jobs-dir DIR       directorio de jobs generados (por defecto en TMPDIR).
#   --wrapper RUTA       ruta a instrumentation/cmdlog.sh.
#   --python RUTA        interprete Python del cluster (por defecto python3).
#   --account CUENTA     cuenta de proyecto Slurm (si procede).
#   --submit             envia los jobs con sbatch (por defecto, solo dry-run).
#   --wait               espera a que terminen los jobs enviados.
#   -h | --help          muestra esta ayuda.
#
# Variables de entorno que consume:
#   CLUSTER, PARTITION, NODES, REPO, DATA_DIR, JOBS_DIR, WRAPPER, PYTHON,
#   ACCOUNT, SUBMIT (1 = enviar), WAIT (1 = esperar), DISCOVERY_RAW (no usada aqui).
#
# Ningun agente lanza jobs por su cuenta (AGENTS.md): sin --submit el script
# solo imprime lo que haria. El envio (--submit) lo confirma una persona.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

usage() {
    cat <<'EOF'
run_discovery.sh - lanzador Slurm del descubrimiento (DISCOVERY.md seccion 2).

Uso: discovery/run_discovery.sh --cluster <nombre> [opciones]

Opciones:
  --cluster NOMBRE     (obligatorio) nombre del cluster.
  --partition NOMBRE   particion declarada a la que limitar el barrido.
  --nodes "n1,n2,..."  lista explicita de nodos (omite sinfo).
  --repo RUTA          copia del repositorio en el cluster (por defecto, este).
  --data-dir DIR       destino de resultados
                       (por defecto <repo>/data/raw/discovery/<cluster>).
  --jobs-dir DIR       directorio de jobs generados (por defecto en TMPDIR).
  --wrapper RUTA       ruta a instrumentation/cmdlog.sh.
  --python RUTA        interprete Python del cluster (por defecto python3).
  --account CUENTA     cuenta de proyecto Slurm (si procede).
  --submit             envia los jobs con sbatch (por defecto, solo dry-run).
  --wait               espera a que terminen los jobs enviados.
  -h | --help          muestra esta ayuda.

Sin --submit el script solo imprime lo que haria. El envio lo confirma una persona.
EOF
}

CLUSTER="${CLUSTER:-}"
PARTITION="${PARTITION:-}"
NODES="${NODES:-}"
REPO="${REPO:-$REPO_ROOT}"
DATA_DIR="${DATA_DIR:-}"
JOBS_DIR="${JOBS_DIR:-}"
WRAPPER="${WRAPPER:-$REPO_ROOT/instrumentation/cmdlog.sh}"
PYTHON="${PYTHON:-python3}"
ACCOUNT="${ACCOUNT:-}"
SUBMIT="${SUBMIT:-0}"
WAIT="${WAIT:-0}"

while [ $# -gt 0 ]; do
    case "$1" in
        --cluster)   CLUSTER="$2"; shift 2 ;;
        --partition) PARTITION="$2"; shift 2 ;;
        --nodes)     NODES="$2"; shift 2 ;;
        --repo)      REPO="$2"; shift 2 ;;
        --data-dir)  DATA_DIR="$2"; shift 2 ;;
        --jobs-dir)  JOBS_DIR="$2"; shift 2 ;;
        --wrapper)   WRAPPER="$2"; shift 2 ;;
        --python)    PYTHON="$2"; shift 2 ;;
        --account)   ACCOUNT="$2"; shift 2 ;;
        --submit)    SUBMIT=1; shift ;;
        --wait)      WAIT=1; shift ;;
        --help|-h)   usage; exit 0 ;;
        *) echo "opcion desconocida: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -z "$CLUSTER" ]; then
    echo "error: falta --cluster" >&2
    exit 2
fi
if [ -z "$DATA_DIR" ]; then
    DATA_DIR="$REPO/data/raw/discovery/$CLUSTER"
fi
if [ -z "$JOBS_DIR" ]; then
    JOBS_DIR="${TMPDIR:-/tmp}/discovery-jobs-$CLUSTER"
fi
mkdir -p "$DATA_DIR" "$JOBS_DIR" || exit 1

RUN_ID="disc-$CLUSTER-$(date -u +%Y%m%dT%H%M%SZ)-$$"

collect_nodes() {
    if [ -n "$NODES" ]; then
        printf '%s\n' "$NODES" | tr ',' '\n' | sed '/^$/d' | sort -u
        return 0
    fi
    if [ ! -f "$WRAPPER" ]; then
        echo "error: wrapper no encontrado: $WRAPPER" >&2
        return 1
    fi
    if [ -n "$PARTITION" ]; then
        CMDLOG_DIR="$DATA_DIR" CMDLOG_RUN_ID="$RUN_ID" \
            bash "$WRAPPER" sinfo -h -N -o '%N' -p "$PARTITION" 2>/dev/null | sort -u
    else
        CMDLOG_DIR="$DATA_DIR" CMDLOG_RUN_ID="$RUN_ID" \
            bash "$WRAPPER" sinfo -h -N -o '%N' 2>/dev/null | sort -u
    fi
}

write_job() {
    node="$1"
    jobfile="$2"
    {
        echo "#!/usr/bin/env bash"
        echo "#SBATCH --job-name=disc_${node}"
        echo "#SBATCH --nodes=1"
        echo "#SBATCH --ntasks=1"
        echo "#SBATCH --exclusive"
        echo "#SBATCH --nodelist=${node}"
        if [ -n "$PARTITION" ]; then
            echo "#SBATCH --partition=${PARTITION}"
        fi
        if [ -n "$ACCOUNT" ]; then
            echo "#SBATCH --account=${ACCOUNT}"
        fi
        echo "#SBATCH --time=00:20:00"
        echo "#SBATCH --output=${JOBS_DIR}/slurm-${node}-%j.out"
        echo "module purge 2>/dev/null || true"
        echo "export CMDLOG_DIR=\"${DATA_DIR}\""
        echo "export CMDLOG_RUN_ID=\"${RUN_ID}\""
        part_opt=""
        if [ -n "$PARTITION" ]; then
            part_opt="--partition \"${PARTITION}\""
        fi
        echo "exec \"${PYTHON}\" \"${REPO}/discovery/collect_node.py\" \\"
        echo "    --mode node --cluster \"${CLUSTER}\" --node \"${node}\" \\"
        echo "    --out-dir \"${DATA_DIR}\" --wrapper \"${WRAPPER}\" ${part_opt}"
    } > "$jobfile"
}

nodes="$(collect_nodes)" || exit 1
if [ -z "$nodes" ]; then
    echo "error: no se han encontrado nodos (revisa --partition/--nodes)" >&2
    exit 1
fi

echo "cluster=$CLUSTER data=$DATA_DIR wrapper=$WRAPPER"
echo "nodos a descubrir:"
printf '%s\n' "$nodes"

ids=""
for node in $nodes; do
    jobfile="$JOBS_DIR/disc_${node}.sbatch"
    write_job "$node" "$jobfile"
    if [ "$SUBMIT" = "1" ]; then
        jobid="$(sbatch --parsable "$jobfile")" || {
            echo "error: fallo sbatch para $node" >&2
            continue
        }
        echo "enviado $node -> job $jobid ($jobfile)"
        ids="$ids $jobid"
    else
        echo "[dry-run] sbatch --exclusive --nodelist=$node $jobfile"
    fi
done

if [ "$SUBMIT" != "1" ]; then
    echo "dry-run: no se ha enviado ningun job (usa --submit para enviar)."
fi

if [ "$WAIT" = "1" ] && [ "$SUBMIT" = "1" ] && [ -n "$ids" ]; then
    joblist="$(echo $ids | tr ' ' ',')"
    echo "esperando a los jobs: $joblist"
    while squeue -h -j "$joblist" 2>/dev/null | grep -q .; do
        sleep 10
    done
    echo "jobs terminados; resultados en $DATA_DIR"
fi

echo "fingerprint: python3 \"$REPO/discovery/fingerprint.py\" --cluster $CLUSTER"
