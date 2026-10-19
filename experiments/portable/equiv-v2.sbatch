#!/usr/bin/env bash
# T49 v2: equivalencia de Xula GNU; orden 2026-10-15-T49-L15b y aclaración.
# Origen inmediato: equiv.sbatch v1 firmado, SHA256
# 9bcbeb74385c563fcef6fd0b358db76cf8ea6b4f6238a48526cd982c96ea77dc.
# Mapas por rank en ficheros propios; humo reutiliza SHA del humo 2736189.
# Origen: experiments/equivalencia.sh, SHA256
# 220dc782be7545238bf8a4c28204234af5f6773c02c2a27480018fc0580fffca.
# R1: 11 rondas (primera calentamiento); humo: 1. STREAM 40M en ambos nodos,
# CPUs declaradas por Slurm; OSU sin -m (filas de análisis 8 B / 4 MiB).
# Binding y transporte GNU por defecto, como equivalencia/calibración.
# No elegir transporte por éxito: exigir evidencia de datos UCX o BML entre nodos.
# QA a-d se ejecuta en el humo firmado; f tiene excepción T49; g al sincronizar.
#SBATCH --job-name=xula-equiv
#SBATCH --exclusive
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=112
#SBATCH --time=00:20:00
set -euo pipefail

check_binary() {
    local bin=$1 expected actual
    test -x "$bin" && test -s "$bin.sha256" || return 4
    expected=$(cat "$bin.sha256")
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 4
    if [ -n "${EXPECTED_STREAM_SHA:-}" ]; then
        test "$expected" = "$EXPECTED_STREAM_SHA" || return 4
    fi
    actual=$(sha256sum < "$bin")
    test "${actual%% *}" = "$expected"
}

check_fingerprints() {
    "$PYTHON_DISCOVERY" -I -B -c '
import json, sys
from pathlib import Path
sys.path.insert(0, "discovery")
import fingerprint as f
base, current, *nodes = sys.argv[1:]
refs = f.load_nodes(base, False)
assert len(refs) == 22 and len(nodes) == len(set(nodes)) == 2
report = f.build(refs)
keys = report["partitions"]["xula4"]["fingerprint_attrs_used"]
assert keys
for node in nodes:
    assert node in report["nodes"], "nodo no descubierto: " + node
    doc = json.loads((Path(current)/(node + ".json")).read_text())
    assert doc["node"] == node and doc["cluster"] == "xula" and doc["partition"] == "xula4"
    values = {}
    for key in keys:
        assert f.observable(doc, key), "atributo perdido: " + node + ":" + key
        value = doc["attributes"][key]["real"]["value"]
        values[key] = f.NORMALIZERS[key](value) if key in f.NORMALIZERS else value
    actual = f.fingerprint_of(values)
    expected = report["nodes"][node]["fingerprint"]
    print(node, "expected=" + expected, "actual=" + actual, "keys=" + ",".join(keys), flush=True)
    assert actual == expected, "huella distinta: " + node
' "$@"
}
check_smoke_negative() {
    local bench=$1 rd=$2 cpus=$3
    shift 3
    "$PYTHON_DISCOVERY" -c '
import re, sys
from pathlib import Path
bench, source, dest = sys.argv[1:]
text = Path(source).read_text()
if bench == "stream":
    text = text.replace("Array size = 40000000", "Array size = 10000000")
else:
    size = "8" if bench == "lat" else "4194304"
    text = re.sub(r"^\s*" + size + r"\s+[0-9.eE+-]+\s*$", "", text, flags=re.M)
Path(dest).write_text(text)
' "$bench" "$rd/run.log" "$rd/negative-from-real.log"
    if check_result "$bench" "$rd/negative-from-real.log" "$cpus" "$@" > "$rd/negative-check.txt" 2>&1; then
        printf 'FALLO: el validador acepta el caso negativo derivado del humo\n' >&2
        return 5
    fi
    printf 'OK: negativo derivado de salida real rechazado\n' >> "$rd/negative-check.txt"
}

check_result() {
    "$PYTHON_DISCOVERY" -c '
import math, re, sys
from pathlib import Path
bench, path, cpus, *nodes = sys.argv[1:]
text = Path(path).read_text()
def expand(s):
    result = set()
    for part in s.split(","):
        a, _, b = part.partition("-")
        result.update(range(int(a), int(b or a)+1))
    return result
maps = []
for file in sorted(Path(path).parent.glob("map-*.txt")):
    match = re.fullmatch(r"EQUIV_MAP host=(\S+) rank=(\d+) cpus=([0-9,-]+)\n", file.read_text())
    assert match and file.name == "map-" + match[2] + ".txt", "fichero de mapa inválido"
    maps.append(match.groups())
expected = {(node, str(rank)) for rank, node in enumerate(nodes)} if bench != "stream" else {(nodes[0], "0")}
assert len(maps) == len(expected) and {(n,r) for n,r,_ in maps} == expected, "host/ranks/mapa"
assert all(expand(c) for _,_,c in maps)
if bench == "stream":
    assert re.search(r"^Array size = 40000000 \(elements\)", text, re.M), "tamaño STREAM"
    assert "Solution Validates: avg error less than" in text, "verificación STREAM"
    for label in ("requested", "counted"):
        assert re.search(r"Number of Threads " + label + r" =\s*" + cpus + r"\s*$", text, re.M), "hilos STREAM"
    threads = re.findall(r"^thread=(\d+) cpus=([0-9,-]+)$", text, re.M)
    assert len(threads) == int(cpus) and {int(t) for t,_ in threads} == set(range(int(cpus))), "afinidad OMP"
    allowed = expand(maps[0][2])
    assert all(expand(c) <= allowed for _,c in threads), "hilo fuera de afinidad Slurm"
    for kernel in ("Copy", "Scale", "Add", "Triad"):
        row = re.search(r"^" + kernel + r":\s+([0-9.eE+-]+)", text, re.M)
        assert row and math.isfinite(float(row[1])) and float(row[1]) > 0, kernel
    transport = "none"
else:
    title = "OSU MPI Latency Test" if bench == "lat" else "OSU MPI Bandwidth Test"
    assert title in text, "cabecera OSU"
    size = 8 if bench == "lat" else 4194304
    rows = re.findall(r"^\s*" + str(size) + r"\s+([0-9.eE+-]+)\s*$", text, re.M)
    assert len(rows) == 1 and math.isfinite(float(rows[0])) and float(rows[0]) > 0, "fila OSU"
    libs = re.findall(r"^EQUIV_LIB host=(\S+) rank=(\d+) ok=yes$", text, re.M)
    assert len(libs) == 2 and set(libs) == expected, "bibliotecas MPI"
    observed = set()
    # UCX INFO 1.14 (ep_cfg) y >=1.15 (inter-node cfg). Solo tags no locales.
    for host, cfg in re.findall(r"\[([a-zA-Z0-9_.-]+):\d+:\d+\].*?(?:ep_cfg\[\d+\]:|inter-node cfg#\d+).*?tag\(([^)]+)\)", text):
        if any(token.split("/")[0] in {"self","posix","sysv","cma","knem","xpmem"} for token in cfg.split()):
            continue
        for token in cfg.split():
            if token.split("/")[0] not in {"self","posix","sysv","cma","knem","xpmem"}:
                if host.split(".")[0] in nodes:
                    observed.add((host.split(".")[0], "ucx:" + token))
    # Open MPI 4.1.8 bml/r2: selección BTL de envío, no componentes disponibles.
    for host, btl, target in re.findall(r"\[([^:\]]+):\d+\].*?mca: bml: Using (\S+) btl for send to .*? on node (\S+)", text):
        host, target = host.split(".")[0], target.split(".")[0]
        if host in nodes and target in nodes and host != target and btl not in {"self","vader","sm"}:
            observed.add((host, "btl:" + btl))
    assert {n for n,_ in observed} == set(nodes), "transporte no observable en ambos nodos"
    transport = ";".join(sorted({t for _,t in observed}))
print("OK transport=" + transport)
' "$@"
}

# Las funciones anteriores se pueden probar localmente sin módulos ni asignación.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then return 0; fi
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")/../..}"
export PERFIL=clusters/perfiles/xula4.env
# shellcheck source=/dev/null
source experiments/portable/perfil.sh
SELF="$REPO/experiments/portable/equiv-v2.sbatch"
BASE="$REPO/data/raw/xula/fase1/discovery"
BIN="$SCRATCH/benchmarks/stream/gnu/xula4/stream_spr"
MODE=${1:-}
case "$MODE" in
    humo|medida|_discover|_rank) ;;
    *) printf 'uso: equiv-v2.sbatch humo|medida\n' >&2; exit 2 ;;
esac
if [ "${DRY_RUN:-0}" = 1 ]; then
    printf 'equiv modo=%s nodos=2 GNU=%s STREAM=40000000 hilos=Slurm reps=%s\n' \
        "$MODE" "${GNU_MODULES[*]}" "$([ "$MODE" = humo ] && printf 1 || printf 11)"
    exit 0
fi
: "${SLURM_JOB_ID:?solo dentro de Slurm}" "${SLURM_SUBMIT_DIR:?falta raíz de envío}"

if [ "$MODE" = _discover ]; then
    node=$2; out=$3
    test "$(hostname -s)" = "$node"
    test -f "$BASE/$node.json"
    module purge
    unset DISCOVERY_MODULES DISCOVERY_CMMSE_MODULES
    export CMDLOG_DIR="$out/commands-$node" CMDLOG_RUN_ID="identity-$SLURM_JOB_ID-$node"
    exec "$PYTHON_DISCOVERY" "$REPO/discovery/collect_node.py" --mode node \
        --cluster xula --partition xula4 --node "$node" --out-dir "$out" --wrapper "$W"
fi

load_stack gnu

if [ "$MODE" = _rank ]; then
    bench=$2; out=$3; cpus=$4
    node=$(hostname -s)
    rank=${OMPI_COMM_WORLD_RANK:-0}
    export CMDLOG_DIR="$out/$node-rank-$rank" CMDLOG_RUN_ID="$bench-$SLURM_JOB_ID-$node-$rank"
    mkdir -p "$CMDLOG_DIR"
    export LEVEL1_RUN_ID="$CMDLOG_RUN_ID" LEVEL1_NODE="$node" LEVEL1_CLUSTER=xula
    export CONTEXT_DIR="$CMDLOG_DIR/context" LEVEL1_STATE_DIR="$CMDLOG_DIR/state"
    export DISCOVERY_DIR="$CMDLOG_DIR/discovery" LEVEL1_MODE=unprivileged LEVEL1_JOB_LOG="$out/run.log"
    mkdir -p "$DISCOVERY_DIR/xula"
    cp "$BASE/$node.json" "$DISCOVERY_DIR/xula/$node.json"
    export UCX_LOG_LEVEL=info OMPI_MCA_pml_base_verbose=10 OMPI_MCA_btl_base_verbose=10
    l1="$REPO/instrumentation/level1_capture.sh"
    if [ "$bench" = stream ]; then
        check_binary "$BIN"
        export OMP_NUM_THREADS="$cpus" OMP_DISPLAY_AFFINITY=TRUE OMP_AFFINITY_FORMAT='thread=%n cpus=%A'
        executable=$BIN
        libs=$(bash "$W" ldd "$BIN")
        printf '%s\n' "$libs"
        ! grep -q 'not found' <<< "$libs"
    else
        executable="$SCRATCH/benchmarks/osu/gnu/xula4/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_$bench"
        case "$bench" in lat) executable="${executable%osu_lat}osu_latency" ;; bw) ;; *) exit 2 ;; esac
        test -x "$executable"
        libs=$(bash "$W" ldd "$executable")
        printf '%s\n' "$libs"
        ! grep -q 'not found' <<< "$libs"
        linked=$(awk '$1 ~ /^libmpi\.so/ && $2 == "=>" {print $3}' <<< "$libs")
        test -n "$linked"
        libdir=$(ompi_info --parsable --path libdir)
        libdir=${libdir#path:libdir:}
        test "$(dirname "$(readlink -f "$linked")")" = "$(readlink -f "$libdir")"
        test "$(dirname "$(readlink -f "$(command -v mpirun)")")" = \
            "$(dirname "$(readlink -f "$(command -v ompi_info)")")"
        printf 'EQUIV_LIB host=%s rank=%s ok=yes\n' "$node" "$rank"
    fi
    bash "$l1" start
    trap 'ec=$?; trap - EXIT; bash "$l1" post || ec=1; bash "$l1" stop || ec=1; exit "$ec"' EXIT
    bash "$l1" pre
    # El shell hijo pasa a ser el benchmark por exec: misma afinidad y PID.
    bash "$W" bash -c 'rank=${OMPI_COMM_WORLD_RANK:-0}; printf "EQUIV_MAP host=%s rank=%s cpus=%s\n" "$(hostname -s)" "$rank" "$(taskset -pc $$ | awk "{print \$NF}")" > "$2/map-$rank.txt"; exec "$1"' _ "$executable" "$out"
    exit 0
fi

test "${SLURM_JOB_NUM_NODES:?}" = 2
export CMDLOG_DIR="$SCRATCH/cc/raw/xula/equivalence/$MODE-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="equiv-$MODE-$SLURM_JOB_ID"
test ! -e "$CMDLOG_DIR"
mkdir -p "$CMDLOG_DIR/discovery"
bash "$W" scontrol show hostnames "${SLURM_JOB_NODELIST:?}" > "$CMDLOG_DIR/nodes.txt"
NODES=()
while IFS= read -r node; do NODES+=("$node"); done < "$CMDLOG_DIR/nodes.txt"
test "${#NODES[@]}" = 2 && test "${NODES[0]}" != "${NODES[1]}"
for node in "${NODES[@]}"; do
    test -f "$BASE/$node.json"
    bash "$W" srun --exclusive -N 1 -n 1 -w "$node" -c "$DECLARED_CORES" \
        bash "$SELF" _discover "$node" "$CMDLOG_DIR/discovery" > "$CMDLOG_DIR/discovery-$node.log" 2>&1
done
check_fingerprints "$BASE" "$CMDLOG_DIR/discovery" "${NODES[@]}" > "$CMDLOG_DIR/fingerprints.txt"
if [ "$MODE" = humo ]; then
    EXPECTED_STREAM_SHA=$(cat "$SCRATCH/cc/raw/xula/equivalence/humo-2736189/stream.sha256")
else
    [[ "${EQUIV_SMOKE_JOB:?falta job del humo}" =~ ^[0-9]+$ ]]
    EXPECTED_STREAM_SHA=$(cat "$SCRATCH/cc/raw/xula/equivalence/humo-$EQUIV_SMOKE_JOB/stream.sha256")
fi
[[ "$EXPECTED_STREAM_SHA" =~ ^[0-9a-f]{64}$ ]]
export EXPECTED_STREAM_SHA
check_binary "$BIN"
cp "$BIN.sha256" "$CMDLOG_DIR/stream.sha256"
REPS=11
[ "$MODE" != humo ] || REPS=1
MANIFEST="$CMDLOG_DIR/manifest.csv"
printf 'bench,nodes,ronda,warmup,exit_code,verificacion,transporte\n' > "$MANIFEST"
for node in "${NODES[@]}"; do
    bash "$W" scontrol show node -o "$node" > "$CMDLOG_DIR/slurm-$node.txt"
    cpus=$(sed -nE 's/.* CPUTot=([0-9]+) .*/\1/p' "$CMDLOG_DIR/slurm-$node.txt")
    test "$cpus" = "$DECLARED_CORES" && test "$cpus" = "${SLURM_CPUS_PER_TASK:?}"
    for ((rep=1; rep<=REPS; rep++)); do
        rd="$CMDLOG_DIR/stream-$node-$rep"; mkdir "$rd"
        ec=0
        bash "$W" srun --exclusive -N 1 -n 1 -w "$node" -c "$cpus" \
            bash "$SELF" _rank stream "$rd" "$cpus" > "$rd/run.log" 2>&1 || ec=$?
        verdict=OK
        check_result stream "$rd/run.log" "$cpus" "$node" > "$rd/check.txt" 2>&1 || verdict=FALLO
        printf 'stream,%s,%s,%s,%s,%s,none\n' "$node" "$rep" "$((rep==1))" "$ec" "$verdict" >> "$MANIFEST"
        test "$ec" = 0 && test "$verdict" = OK || exit 5
        if [ "$MODE" = humo ]; then check_smoke_negative stream "$rd" "$cpus" "$node"; fi
    done
done
for bench in lat bw; do
    for ((rep=1; rep<=REPS; rep++)); do
        rd="$CMDLOG_DIR/$bench-$rep"; mkdir "$rd"
        ec=0
        bash "$W" mpirun -np 2 --map-by ppr:1:node --host "${NODES[0]},${NODES[1]}" \
            bash "$SELF" _rank "$bench" "$rd" 1 > "$rd/run.log" 2>&1 || ec=$?
        verdict=OK
        check_result "$bench" "$rd/run.log" 1 "${NODES[@]}" > "$rd/check.txt" 2>&1 || verdict=FALLO
        transport=$(sed -n 's/^OK transport=//p' "$rd/check.txt")
        printf '%s,%s;%s,%s,%s,%s,%s,%s\n' "$bench" "${NODES[0]}" "${NODES[1]}" "$rep" "$((rep==1))" "$ec" "$verdict" "${transport:-sin-observar}" >> "$MANIFEST"
        test "$ec" = 0 && test "$verdict" = OK || exit 5
        if [ "$MODE" = humo ]; then check_smoke_negative "$bench" "$rd" 1 "${NODES[@]}"; fi
    done
done
test "$(wc -l < "$MANIFEST")" -eq "$((1+4*REPS))"
printf 'OK: %s runs; cobertura=%s,%s\n' "$((4*REPS))" "${NODES[0]}" "${NODES[1]}"
