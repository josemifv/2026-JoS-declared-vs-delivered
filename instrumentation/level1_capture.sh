#!/usr/bin/env bash
# level1_capture.sh - captura de contexto de nivel 1 por run (AGENTS.md, Instrumentacion).
# Solo bash + python3 stdlib. Portabilidad (DISCOVERY.md 6, R14): si un comando o
# una ruta no existe, el atributo se registra como no observable y se continua.
# Subcomandos: start | pre | post | stop   (ver instrumentation/README.md)
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
CMDLOG="$SELF_DIR/cmdlog.sh"

RUN_ID="${LEVEL1_RUN_ID:-${SLURM_JOB_ID:-local-$(date -u +%Y%m%dT%H%M%SZ)-$$}}"
CONTEXT_DIR="${CONTEXT_DIR:-data/raw/context}"
STATE="${LEVEL1_STATE_DIR:-$PWD/.level1_state}/$RUN_ID"
INTERVAL="${LEVEL1_INTERVAL:-1}"
IB_SETTLE="${LEVEL1_IB_SETTLE:-2}"
DISCOVERY_DIR="${DISCOVERY_DIR:-data/raw/discovery}"
DRY_RUN="${DRY_RUN:-0}"
CLUSTER="${LEVEL1_CLUSTER:-}"
JOB_LOG="${LEVEL1_JOB_LOG:-}"
MPIP_LIB="${MPIP_LIB:-}"

export CMDLOG_DIR="${CMDLOG_DIR:-$CONTEXT_DIR/cmdlog}"
export CMDLOG_RUN_ID="$RUN_ID"

log() { printf '%s\n' "$*" >&2; }
w() { "$CMDLOG" "$@"; }
have() { command -v "$1" >/dev/null 2>&1; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

choose_mode() {
  case "${LEVEL1_MODE:-auto}" in
    privileged|unprivileged) printf '%s' "$LEVEL1_MODE" ;;
    *)
      if [ "$DRY_RUN" = "1" ]; then printf '%s' unprivileged
      elif [ -r /sys/class/powercap/intel-rapl:0/energy_uj ]; then printf '%s' privileged
      else printf '%s' unprivileged; fi ;;
  esac
}
read_mode() { if [ -f "$STATE/mode" ]; then cat "$STATE/mode"; else choose_mode; fi; }
mode_source() { if [ "${LEVEL1_MODE:-auto}" = auto ]; then printf '%s' auto; else printf '%s' env; fi; }

resolve_node() {
  if [ -n "${LEVEL1_NODE:-}" ]; then printf '%s' "$LEVEL1_NODE"; return; fi
  n="$(w hostname 2>/dev/null | head -n 1)"
  if [ -n "$n" ]; then printf '%s' "$n"; else printf '%s' unknown; fi
}

# --- captura de contadores IB (sysfs sin privilegios; perfquery como respaldo) -
capture_ib() {
  outfile="$1"
  rawfile="$STATE/ib_raw_$(basename "$outfile" .json).txt"
  : > "$rawfile"
  if [ ! -d /sys/class/infiniband ] && have perfquery; then
    w perfquery > "$rawfile" 2>&1 || true
  fi
  python3 - "$outfile" "$rawfile" <<'PY'
import json, os, sys, time
outfile, rawfile = sys.argv[1], sys.argv[2]
rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
       "source": "none", "observable": False, "devices": {}, "raw": None}
base = "/sys/class/infiniband"
try:
    devs = sorted(os.listdir(base)) if os.path.isdir(base) else []
except OSError:
    devs = []
if devs:
    rec["source"] = "sysfs"
    rec["observable"] = True
    for d in devs:
        pb = os.path.join(base, d, "ports")
        try:
            ports = sorted(os.listdir(pb))
        except OSError:
            continue
        for prt in ports:
            cd = os.path.join(pb, prt, "counters")
            counters = {}
            try:
                names = sorted(os.listdir(cd))
            except OSError:
                names = []
            for n in names:
                try:
                    with open(os.path.join(cd, n)) as f:
                        counters[n] = int(f.read().strip())
                except (OSError, ValueError):
                    pass
            rec["devices"].setdefault(d, {})[prt] = counters
else:
    try:
        with open(rawfile) as f:
            raw = f.read()
    except OSError:
        raw = ""
    if raw.strip():
        rec["source"] = "perfquery"
        rec["observable"] = True
        rec["raw"] = raw
with open(outfile, "w") as f:
    json.dump(rec, f, ensure_ascii=False)
PY
}

# --- start ---------------------------------------------------------------------
do_start() {
  mkdir -p "$STATE" "$CONTEXT_DIR"
  NODE="$(resolve_node)"
  MODE="$(choose_mode)"
  START_TS="$(now)"
  printf '%s' "$MODE" > "$STATE/mode"
  printf '%s' "$NODE" > "$STATE/node"

  # 1) muestreo de frecuencia/energia cada INTERVAL s, en segundo plano.
  cat > "$STATE/sample.py" <<'PY'
import json, os, sys, time, glob

out, interval = sys.argv[1], float(sys.argv[2])
stopfile = out + ".stop"

def freq():
    vals = []
    for p in sorted(glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq")):
        try:
            with open(p) as f:
                vals.append(int(f.read().strip()))
        except (OSError, ValueError):
            return None
    return vals or None

def energy():
    for p in sorted(glob.glob("/sys/class/powercap/intel-rapl:*/energy_uj")):
        try:
            with open(p) as f:
                return int(f.read().strip())
        except (OSError, ValueError):
            return None
    return None

with open(out, "a") as fh:
    while not os.path.exists(stopfile):
        rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
               "freq_khz": freq(), "energy_uj": energy()}
        fh.write(json.dumps(rec) + "\n")
        fh.flush()
        time.sleep(interval)
PY
  nohup python3 "$STATE/sample.py" "$STATE/freq.jsonl" "$INTERVAL" \
    >"$STATE/sampler.log" 2>&1 &
  echo $! > "$STATE/sampler.pid"

  # 2) atributos estaticos capturados en este proceso.
  if [ -r /proc/self/status ]; then
    aff=""
    while IFS= read -r line; do
      case "$line" in Cpus_allowed_list:*) aff="${line#Cpus_allowed_list:}"; aff="${aff# }" ;; esac
    done < /proc/self/status
    printf '%s' "$aff" > "$STATE/affinity.txt"
  else
    : > "$STATE/affinity.txt"
  fi
  if w taskset -pc $$ > "$STATE/taskset.txt" 2>&1; then taskset_ok=1; else taskset_ok=0; fi
  env | grep -E '^(UCX_|OMPI_|I_MPI_|OMP_|FI_|PMI_)' > "$STATE/env.txt" 2>/dev/null || : > "$STATE/env.txt"
  if w bash -lc 'module list' > "$STATE/modules.txt" 2>&1 && [ -s "$STATE/modules.txt" ]; then mods_ok=1; else mods_ok=0; fi

  L1_RUN_ID="$RUN_ID" L1_NODE="$NODE" L1_CLUSTER="$CLUSTER" L1_MODE="$MODE" \
  L1_MODE_SOURCE="$(mode_source)" L1_START="$START_TS" L1_INTERVAL="$INTERVAL" \
  L1_IB_SETTLE="$IB_SETTLE" L1_DRY_RUN="$DRY_RUN" L1_STATE="$STATE" \
  L1_DISCOVERY_DIR="$DISCOVERY_DIR" L1_MPIP_LIB="$MPIP_LIB" \
  L1_TASKSET_OK="$taskset_ok" L1_MODS_OK="$mods_ok" \
  L1_CAP_TURBOSTAT="$(have turbostat && echo true || echo false)" \
  L1_CAP_PERFQUERY="$(have perfquery && echo true || echo false)" \
  L1_CAP_TASKSET="$(have taskset && echo true || echo false)" \
  L1_CAP_SYSFS_CPUFREQ="$( [ -d /sys/devices/system/cpu/cpu0/cpufreq ] && echo true || echo false )" \
  L1_CAP_SYSFS_RAPL="$( [ -r /sys/class/powercap/intel-rapl:0/energy_uj ] && echo true || echo false )" \
  L1_CAP_SYSFS_IB="$( [ -d /sys/class/infiniband ] && echo true || echo false )" \
  L1_JOB_LOG="$JOB_LOG" \
  python3 - <<'PY'
import hashlib, json, os

S = os.environ["L1_STATE"]

def rfile(name):
    try:
        with open(os.path.join(S, name)) as f:
            return f.read()
    except OSError:
        return ""

env = {}
for line in rfile("env.txt").splitlines():
    if "=" in line:
        k, v = line.split("=", 1)
        env[k] = v

aff = rfile("affinity.txt").strip()
taskset_ok = os.environ["L1_TASKSET_OK"] == "1"
taskset = rfile("taskset.txt").strip() if taskset_ok else ""

def fingerprint(discovery_dir, cluster, node):
    cands = []
    if cluster:
        cands.append(os.path.join(discovery_dir, cluster, node + ".json"))
    else:
        try:
            for c in sorted(os.listdir(discovery_dir)):
                cands.append(os.path.join(discovery_dir, c, node + ".json"))
        except OSError:
            pass
    for p in cands:
        if os.path.isfile(p):
            obj = None
            try:
                with open(p) as f:
                    obj = json.load(f)
            except (OSError, ValueError):
                obj = None
            if isinstance(obj, dict) and "fingerprint" in obj:
                return {"observable": True, "source": "discovery-json", "node": node,
                        "path": p, "fingerprint": obj["fingerprint"]}
            with open(p, "rb") as f:
                data = f.read()
            return {"observable": True, "source": "discovery-file-hash", "node": node,
                    "path": p, "fingerprint": "sha256:" + hashlib.sha256(data).hexdigest()}
    return {"observable": False, "node": node, "reason": "sin fichero de descubrimiento"}

mpip_lib = os.environ["L1_MPIP_LIB"]
mpip = {"available": bool(mpip_lib and os.path.isfile(mpip_lib)), "lib": mpip_lib or None}
if mpip["available"]:
    mpip["ld_preload"] = mpip_lib
else:
    mpip["reason"] = "MPIP_LIB no definido o inexistente"

transport_env = {k: env[k] for k in ("UCX_LOG_LEVEL", "I_MPI_DEBUG", "FI_LOG_LEVEL") if k in env}
job_log = os.environ["L1_JOB_LOG"]

meta = {
    "schema": "level1/1",
    "run_id": os.environ["L1_RUN_ID"],
    "started_at": os.environ["L1_START"],
    "node": os.environ["L1_NODE"],
    "cluster": os.environ["L1_CLUSTER"] or None,
    "dry_run": os.environ["L1_DRY_RUN"] == "1",
    "mode": {"level1": os.environ["L1_MODE"], "source": os.environ["L1_MODE_SOURCE"]},
    "interval_s": float(os.environ["L1_INTERVAL"]),
    "capabilities": {
        "turbostat": os.environ["L1_CAP_TURBOSTAT"] == "true",
        "perfquery": os.environ["L1_CAP_PERFQUERY"] == "true",
        "taskset": os.environ["L1_CAP_TASKSET"] == "true",
        "sysfs_cpufreq": os.environ["L1_CAP_SYSFS_CPUFREQ"] == "true",
        "sysfs_rapl": os.environ["L1_CAP_SYSFS_RAPL"] == "true",
        "sysfs_infiniband": os.environ["L1_CAP_SYSFS_IB"] == "true",
    },
    "affinity": {"cpus_allowed_list": aff or None, "taskset": taskset or None,
                 "observable": bool(aff or taskset_ok)},
    "fingerprint": fingerprint(os.environ["L1_DISCOVERY_DIR"],
                               os.environ["L1_CLUSTER"], os.environ["L1_NODE"]),
    "env": env,
    "modules": {"observable": os.environ["L1_MODS_OK"] == "1",
                "list": rfile("modules.txt") if os.environ["L1_MODS_OK"] == "1" else ""},
    "transport_log": {"env_vars": transport_env, "log_path": job_log or None,
                      "observable": bool(job_log)},
    "mpip": mpip,
}
with open(os.path.join(S, "meta.json"), "w") as f:
    json.dump(meta, f, ensure_ascii=False)
PY

  log "level1 start: run_id=$RUN_ID node=$NODE mode=$MODE estado=$STATE"
}

# --- pre / post ----------------------------------------------------------------
do_ib() {
  [ -d "$STATE" ] || { log "level1: no hay start en $STATE"; exit 2; }
  mkdir -p "$STATE"
  capture_ib "$STATE/ib_$1.json"
  log "level1 $1: contadores IB capturados ($(read_mode))"
}

do_post() {
  [ -d "$STATE" ] || { log "level1: no hay start en $STATE"; exit 2; }
  sleep "$IB_SETTLE"   # espera de transmision antes de leer los contadores
  capture_ib "$STATE/ib_post.json"
  log "level1 post: contadores IB capturados tras $IB_SETTLE s"
}

# --- stop ----------------------------------------------------------------------
do_stop() {
  [ -d "$STATE" ] || { log "level1: no hay start en $STATE"; exit 2; }
  if [ -f "$STATE/sampler.pid" ]; then
    pid="$(cat "$STATE/sampler.pid")"
    : > "$STATE/freq.jsonl.stop"
    kill "$pid" 2>/dev/null || true
    sleep 1
  fi
  mkdir -p "$CONTEXT_DIR"
  L1_RUN_ID="$RUN_ID" L1_CONTEXT_DIR="$CONTEXT_DIR" L1_STATE="$STATE" \
  L1_IB_SETTLE="$IB_SETTLE" L1_JOB_LOG="$JOB_LOG" \
  python3 - <<'PY'
import hashlib, json, os, shutil, statistics, time

S = os.environ["L1_STATE"]
CTX = os.environ["L1_CONTEXT_DIR"]
RUN = os.environ["L1_RUN_ID"]
settle = float(os.environ["L1_IB_SETTLE"])

def load(name, default):
    try:
        with open(os.path.join(S, name)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default

final = load("meta.json", {"run_id": RUN, "schema": "level1/1"})
final["stopped_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

# log del job: se recoge y se preserva (el parseo del transporte es del notebook).
joblog = {"observable": False}
jl = os.environ.get("L1_JOB_LOG", "")
if jl and os.path.isfile(jl):
    with open(jl, "rb") as f:
        data = f.read()
    dst = os.path.join(CTX, RUN + ".log")
    shutil.copyfile(jl, dst)
    joblog = {"observable": True, "log_path": jl, "preserved_path": dst,
              "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
final["job_log"] = joblog

# contadores IB antes/despues y delta.
pre = load("ib_pre.json", {"source": "none", "observable": False, "devices": {}})
post = load("ib_post.json", {"source": "none", "observable": False, "devices": {}})
delta = {}
pd, qd = pre.get("devices", {}), post.get("devices", {})
for d, ports in qd.items():
    for prt, counters in ports.items():
        a = pd.get(d, {}).get(prt, {})
        dd = {k: counters[k] - a[k] for k in counters
              if k in a and isinstance(a[k], int) and isinstance(counters[k], int)}
        if dd:
            delta.setdefault(d, {})[prt] = dd
final["ib_counters"] = {"settle_s": settle, "source": post.get("source") or pre.get("source"),
                        "observable": bool(pre.get("observable") or post.get("observable")),
                        "pre": pre, "post": post, "delta": delta}

# muestreo de frecuencia/energia: resumen + fichero crudo preservado.
samples = []
spath = os.path.join(S, "freq.jsonl")
if os.path.isfile(spath):
    with open(spath) as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    samples.append(json.loads(line))
                except ValueError:
                    pass
freqs, energies = [], []
for s in samples:
    if isinstance(s.get("freq_khz"), list):
        freqs.extend(s["freq_khz"])
    if isinstance(s.get("energy_uj"), int):
        energies.append(s["energy_uj"])

def stats(vals):
    if not vals:
        return {"observable": False}
    return {"observable": True, "min": min(vals), "max": max(vals),
            "median": statistics.median(vals), "n": len(vals)}

sampling = {"interval_s": final.get("interval_s"), "n_samples": len(samples),
            "freq_khz": stats(freqs), "energy_uj": stats(energies)}
if samples:
    dst = os.path.join(CTX, RUN + ".freq.jsonl")
    shutil.copyfile(spath, dst)
    with open(dst, "rb") as f:
        sampling["samples_path"] = dst
        sampling["samples_sha256"] = hashlib.sha256(f.read()).hexdigest()
final["sampling"] = sampling

# atributos no observables (portabilidad).
no = []
if not final.get("fingerprint", {}).get("observable"):
    no.append("fingerprint")
if not final.get("affinity", {}).get("observable"):
    no.append("affinity")
if not final.get("modules", {}).get("observable"):
    no.append("modules")
if not final.get("transport_log", {}).get("observable"):
    no.append("transport_log")
if not final.get("mpip", {}).get("available"):
    no.append("mpip")
if not final["ib_counters"]["observable"]:
    no.append("ib_counters")
if not sampling["freq_khz"]["observable"]:
    no.append("freq_khz")
if not sampling["energy_uj"]["observable"]:
    no.append("energy_uj")
final["not_observable"] = no

out = os.path.join(CTX, RUN + ".json")
with open(out, "w") as f:
    json.dump(final, f, ensure_ascii=False, indent=2)
print(out)
PY
  log "level1 stop: contexto escrito en $CONTEXT_DIR/$RUN_ID.json"
}

case "${1:-}" in
  start) do_start ;;
  pre)   do_ib pre ;;
  post)  do_post ;;
  stop)  do_stop ;;
  *) echo "uso: level1_capture.sh {start|pre|post|stop}" >&2; exit 2 ;;
esac
