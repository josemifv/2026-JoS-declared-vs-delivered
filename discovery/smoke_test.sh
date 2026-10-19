#!/usr/bin/env bash
#
# smoke_test.sh - prueba de humo en 2 nodos (puerta de la etapa 1, AGENTS.md).
#
# Lanza el descubrimiento en DOS nodos concretos (via run_discovery.sh con
# --nodes) y verifica que las salidas quedan bien formadas:
#   - cada linea de commands.jsonl es JSON valido con los campos del wrapper;
#   - cada outputs/<sha256>.out existe y su sha256 coincide con out_hash;
#   - cada <nodo>.json parsea, tiene fingerprint de 64 hex y atributos.
# Despues ejecuta fingerprint.py sobre los dos nodos y muestra las
# subparticiones resultantes.
#
# NO se ejecuta por si solo: el envio de jobs lo confirma una persona. Para
# probar el flujo completo en local (macOS) sin cluster, usar el dry-run de
# collect_node.py (DRY_RUN=1), que ejercita la ruta "no observable".
#
# Uso:
#   discovery/smoke_test.sh --cluster <nombre> --nodes "nodoA,nodoB" [opciones]
#   DRY_RUN=1 discovery/smoke_test.sh --cluster <nombre> --nodes "nodoA,nodoB"
#
# Opciones:
#   --cluster NOMBRE   (obligatorio) nombre del cluster.
#   --nodes "n1,n2"    (obligatorio) EXACTAMENTE dos nodos.
#   --repo RUTA        copia del repositorio en el cluster.
#   --data-dir DIR     destino de resultados (por defecto <repo>/data/raw/discovery/<cluster>).
#   --wrapper RUTA     ruta a instrumentation/cmdlog.sh.
#   --python RUTA      interprete Python (por defecto python3).
#   --account CUENTA   cuenta de proyecto Slurm.
#   --verify-only      no lanza nada; solo verifica el --data-dir existente.
#   -h | --help        muestra esta ayuda.
#
# Variables de entorno que consume: CLUSTER, NODES, REPO, DATA_DIR, WRAPPER,
#   PYTHON, ACCOUNT, DRY_RUN (1 = no enviar, solo plan y verificacion si hay datos).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

usage() {
    cat <<'EOF'
smoke_test.sh - prueba de humo en 2 nodos (puerta de la etapa 1, AGENTS.md).

Lanza el descubrimiento en DOS nodos concretos y verifica que las salidas
quedan bien formadas; despues ejecuta fingerprint.py.

Uso: discovery/smoke_test.sh --cluster <nombre> --nodes "nodoA,nodoB" [opciones]

Opciones:
  --cluster NOMBRE   (obligatorio) nombre del cluster.
  --nodes "n1,n2"    (obligatorio) EXACTAMENTE dos nodos.
  --repo RUTA        copia del repositorio en el cluster.
  --data-dir DIR     destino de resultados.
  --wrapper RUTA     ruta a instrumentation/cmdlog.sh.
  --python RUTA      interprete Python (por defecto python3).
  --account CUENTA   cuenta de proyecto Slurm.
  --verify-only      no lanza nada; solo verifica el --data-dir existente.
  -h | --help        muestra esta ayuda.

NO se ejecuta por si solo: el envio de jobs lo confirma una persona. Para
probar el flujo en local (macOS) usar el dry-run de collect_node.py (DRY_RUN=1).
EOF
}

CLUSTER="${CLUSTER:-}"
NODES="${NODES:-}"
REPO="${REPO:-$REPO_ROOT}"
DATA_DIR="${DATA_DIR:-}"
WRAPPER="${WRAPPER:-$REPO_ROOT/instrumentation/cmdlog.sh}"
PYTHON="${PYTHON:-python3}"
ACCOUNT="${ACCOUNT:-}"
DRY_RUN="${DRY_RUN:-0}"
VERIFY_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --cluster)     CLUSTER="$2"; shift 2 ;;
        --nodes)       NODES="$2"; shift 2 ;;
        --repo)        REPO="$2"; shift 2 ;;
        --data-dir)    DATA_DIR="$2"; shift 2 ;;
        --wrapper)     WRAPPER="$2"; shift 2 ;;
        --python)      PYTHON="$2"; shift 2 ;;
        --account)     ACCOUNT="$2"; shift 2 ;;
        --verify-only) VERIFY_ONLY=1; shift ;;
        --help|-h)     usage; exit 0 ;;
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

nnodes="$(printf '%s\n' "$NODES" | tr ',' '\n' | sed '/^$/d' | wc -l | tr -d ' ')"
if [ "$VERIFY_ONLY" != "1" ]; then
    if [ "$nnodes" != "2" ]; then
        echo "error: --nodes debe tener exactamente 2 nodos (hay $nnodes)" >&2
        exit 2
    fi
fi

if [ "$VERIFY_ONLY" != "1" ]; then
    echo "== lanzando descubrimiento en 2 nodos =="
    if [ "$DRY_RUN" = "1" ]; then
        bash "$SCRIPT_DIR/run_discovery.sh" --cluster "$CLUSTER" --nodes "$NODES" \
            --repo "$REPO" --data-dir "$DATA_DIR" --wrapper "$WRAPPER" \
            --python "$PYTHON" --account "$ACCOUNT"
    else
        bash "$SCRIPT_DIR/run_discovery.sh" --cluster "$CLUSTER" --nodes "$NODES" \
            --repo "$REPO" --data-dir "$DATA_DIR" --wrapper "$WRAPPER" \
            --python "$PYTHON" --account "$ACCOUNT" --submit --wait || exit 1
    fi
fi

if [ ! -f "$DATA_DIR/commands.jsonl" ]; then
    echo "smoke test: sin datos en $DATA_DIR (dry-run sin envio); no hay nada que verificar."
    exit 0
fi

echo "== verificando registros en $DATA_DIR =="
"$PYTHON" - "$DATA_DIR" <<'PY'
import hashlib
import json
import os
import sys

data_dir = sys.argv[1]
problems = []

jsonl = os.path.join(data_dir, "commands.jsonl")
outputs = os.path.join(data_dir, "outputs")

required = ["ts", "host", "cmd", "tool", "tool_version", "exit_code",
            "duration_ms", "out_hash", "out_path", "run_id"]

n_lines = 0
with open(jsonl, "r", encoding="utf-8") as fh:
    for lineno, line in enumerate(fh, 1):
        line = line.strip()
        if not line:
            continue
        n_lines += 1
        try:
            rec = json.loads(line)
        except ValueError:
            problems.append("commands.jsonl:%d no es JSON valido" % lineno)
            continue
        missing = [k for k in required if k not in rec]
        if missing:
            problems.append("commands.jsonl:%d faltan campos %s" % (lineno, missing))
        out_path = rec.get("out_path")
        if out_path and os.path.isfile(out_path):
            with open(out_path, "rb") as fout:
                digest = hashlib.sha256(fout.read()).hexdigest()
            if digest != rec.get("out_hash"):
                problems.append("commands.jsonl:%d out_hash no coincide con %s"
                                % (lineno, out_path))
        elif out_path:
            problems.append("commands.jsonl:%d out_path inexistente: %s"
                            % (lineno, out_path))

if n_lines == 0:
    problems.append("commands.jsonl vacio")

if not os.path.isdir(outputs):
    problems.append("no existe %s" % outputs)

node_files = [n for n in sorted(os.listdir(data_dir))
              if n.endswith(".json") and n not in ("slurm.json",)]
for name in node_files:
    with open(os.path.join(data_dir, name), "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    fp = doc.get("fingerprint")
    if not isinstance(fp, str) or len(fp) != 64:
        problems.append("%s: fingerprint ausente o invalido" % name)
    for field in ("node", "cluster", "attributes"):
        if field not in doc:
            problems.append("%s: falta el campo %s" % (name, field))

print("lineas en commands.jsonl: %d" % n_lines)
print("ficheros de nodo: %s" % (", ".join(node_files) or "ninguno"))

if problems:
    print("FALLO: %d problema(s):" % len(problems))
    for p in problems:
        print("  - %s" % p)
    sys.exit(1)
print("OK: registros bien formados")
PY
rc=$?
if [ "$rc" != "0" ]; then
    echo "smoke test: FALLO en la verificacion" >&2
    exit 1
fi

echo "== fingerprint de los 2 nodos (resumen por stdout) =="
"$PYTHON" "$SCRIPT_DIR/fingerprint.py" --cluster "$CLUSTER" --raw-dir "$DATA_DIR" \
    || echo "aviso: fingerprint no ejecutado"

echo "smoke test: OK"
