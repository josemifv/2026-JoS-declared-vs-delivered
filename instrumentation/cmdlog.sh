#!/usr/bin/env bash
# cmdlog.sh - ejecuta un comando, reproduce su salida y registra una linea JSONL.
# Ver instrumentation/README.md (contrato). Solo bash + python3 stdlib.
# Uso: cmdlog.sh <comando> [args...]
set -u

if [ "$#" -lt 1 ]; then
  echo "uso: cmdlog.sh <comando> [args...]" >&2
  exit 2
fi

CMDLOG_DIR="${CMDLOG_DIR:-$PWD/cmdlog}"
RUN_ID="${CMDLOG_RUN_ID:-}"
mkdir -p "$CMDLOG_DIR/outputs" "$CMDLOG_DIR/tool_versions"

tool="$(basename "$1")"

# Ruta real del ejecutable: la version se captura del binario que se ejecuta de
# verdad y la cache se indexa por (nombre, ruta resuelta). Asi no se mezclan
# implementaciones distintas con el mismo nombre dentro de un job: p. ej. el
# mpirun de Open MPI (pila gcc) y el de Intel MPI (pila intel) compartian antes
# tool_versions/mpirun.txt y todos los runs quedaban con la version del primero.
if command -v "$1" >/dev/null 2>&1; then
  tool_path="$(command -v "$1")"
else
  tool_path="$1"
fi
key="$(python3 -c 'import hashlib,sys; sys.stdout.write(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:8])' "$tool_path")"
ver_file="$CMDLOG_DIR/tool_versions/$tool.$key.txt"
if [ -f "$ver_file" ]; then
  tool_version="$(cat "$ver_file")"
else
  tool_version=""
  if command -v "$tool_path" >/dev/null 2>&1; then
    tool_version="$("$tool_path" --version 2>&1 | head -n 1)"
  fi
  printf '%s\n' "$tool_version" > "$ver_file"
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
host="$(hostname 2>/dev/null || echo unknown)"

tmpdir="${TMPDIR:-/tmp}"
argv_file="$(mktemp "$tmpdir/cmdlog_argv.XXXXXX")"
out_tmp="$(mktemp "$tmpdir/cmdlog_out.XXXXXX")"
# argv en fichero NUL-delimitado (robusto ante espacios, comillas y saltos).
printf '%s\0' "$@" > "$argv_file"

start_ms="$(python3 -c 'import time;print(int(time.time()*1000))')"
"$@" > "$out_tmp" 2>&1
exit_code=$?
end_ms="$(python3 -c 'import time;print(int(time.time()*1000))')"
duration_ms=$((end_ms - start_ms))

CMDLOG_DIR="$CMDLOG_DIR" CMDLOG_RUN_ID="$RUN_ID" CMDLOG_TS="$ts" \
CMDLOG_HOST="$host" CMDLOG_TOOL="$tool" CMDLOG_TOOL_PATH="$tool_path" \
CMDLOG_TOOL_VERSION="$tool_version" \
CMDLOG_EXIT="$exit_code" CMDLOG_DURATION_MS="$duration_ms" \
CMDLOG_ARGV_FILE="$argv_file" CMDLOG_OUT_TMP="$out_tmp" python3 - <<'PY'
import hashlib, json, os, shutil

d = os.environ["CMDLOG_DIR"]
with open(os.environ["CMDLOG_ARGV_FILE"], "rb") as f:
    argv = [a.decode("utf-8", "replace") for a in f.read().split(b"\0") if a]
with open(os.environ["CMDLOG_OUT_TMP"], "rb") as f:
    data = f.read()
h = hashlib.sha256(data).hexdigest()
out_path = os.path.join(d, "outputs", h + ".out")
if not os.path.exists(out_path):
    shutil.copyfile(os.environ["CMDLOG_OUT_TMP"], out_path)

rec = {
    "ts": os.environ["CMDLOG_TS"],
    "host": os.environ["CMDLOG_HOST"],
    "cmd": argv,
    "tool": os.environ["CMDLOG_TOOL"],
    "tool_path": os.environ.get("CMDLOG_TOOL_PATH", ""),
    "tool_version": os.environ["CMDLOG_TOOL_VERSION"],
    "exit_code": int(os.environ["CMDLOG_EXIT"]),
    "duration_ms": int(os.environ["CMDLOG_DURATION_MS"]),
    "out_hash": h,
    "out_path": out_path,
    "run_id": os.environ.get("CMDLOG_RUN_ID", ""),
}
with open(os.path.join(d, "commands.jsonl"), "a") as f:
    f.write(json.dumps(rec, ensure_ascii=False) + "\n")
PY
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "cmdlog: fallo al registrar el comando (python rc=$rc)" >&2
fi

cat "$out_tmp"
rm -f "$out_tmp" "$argv_file"
exit "$exit_code"
