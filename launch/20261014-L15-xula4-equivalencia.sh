#!/usr/bin/env bash
# T49 — L15: equivalencia GNU 40M de los 22 nodos conocidos de Xula xula4.
# Autoriza: órdenes 2026-10-14-T49-xula4-equivalencia.md,
# 2026-10-14-T49-continuacion-stream.md y 2026-10-14-T49-stream-40M.md,
# archivadas en informes/ordenes/; DEVIATIONS (tres entradas T49), R1/R14.
# Commit de equiv.sbatch: 8fd785b823a4cec8af4a3ca7b61f4d6f548e0eb5.
# 1 humo + 15 medidas, 2 nodos exclusivos/job, 112 CPUs/tarea, 1 tarea/nodo.
# Todos 00:20:00: 16 × 2 × 20/60 = 10,666667 nodo-hora reservadas (no consumo real).
# Humo: 4 runs (2 STREAM + lat + bw), 1 ronda; solo humo compila 40M.
# Medida/job: 44 runs (22 STREAM + 11 lat + 11 bw), primera ronda calentamiento.
# Total: 664 runs; 332 STREAM, 166 lat y 166 bw, incluidos calentamientos.
# Exclusiones: xula5001,xula5002,xula5202,xula5403,xula5404,xula5603.
# Sin --nodelist ni pares fijos: Slurm elige; cobertura real se informa al sync.
# Las 15 medidas afterok del humo y kill-on-invalid-dep=yes; QA a-d dentro del
# humo de la misma forma, f exceptuado por orden; g al sync; h firma y puertas.
# Desplegar también los 22 JSON en data/raw/xula/fase1/discovery (inmutables).
# Raw scratch: cc/raw/xula/equivalence/{humo,medida}-JOBID; stdout en checkout
# data/raw/xula/equivalence/. Sync con --ignore-existing a data/raw/xula/equivalence/.
# NO ejecutar sin firma SHA completa. Tras aprobación:
# SIGNED_LAUNCH_SHA=<firma> bash launch/20261014-L15-xula4-equivalencia.sh
# DRY_RUN=1: solo puertas locales y 16 líneas; sin SSH, módulos ni sbatch real.
set -euo pipefail
LAUNCH_REL=launch/20261014-L15-xula4-equivalencia.sh
check_sha() {
    local actual
    actual=$(sha256sum < "$1")
    test "${actual%% *}" = "$2" || { printf 'sha256 MAL: %s\n' "$1" >&2; exit 4; }
    printf 'sha256 OK: %s\n' "$1"
}
if [ "${PORTABLE_REMOTE:-0}" != 1 ]; then
    LAUNCH_FILE="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    cd "$(dirname "$LAUNCH_FILE")/.."
    if [ "${DRY_RUN:-0}" != 1 ]; then
        : "${SIGNED_LAUNCH_SHA:?falta firma SHA completa}"
        check_sha "$LAUNCH_REL" "$SIGNED_LAUNCH_SHA"
        source clusters/local.env
        : "${XULA_REPO:?}"
        EXPECTED_DEPLOY_COMMIT=$(git rev-parse HEAD)
        { printf 'cd %q\nexport PORTABLE_REMOTE=1\nexport EXPECTED_DEPLOY_COMMIT=%q\nexport SIGNED_LAUNCH_SHA=%q\n' \
            "$XULA_REPO" "$EXPECTED_DEPLOY_COMMIT" "$SIGNED_LAUNCH_SHA"; cat "$LAUNCH_FILE"; } | ssh xula 'bash -s'
        exit "$?"
    fi
fi
if [ "${DRY_RUN:-0}" != 1 ]; then
    : "${SIGNED_LAUNCH_SHA:?falta firma SHA completa}" "${EXPECTED_DEPLOY_COMMIT:?falta commit desplegado}"
    check_sha "$LAUNCH_REL" "$SIGNED_LAUNCH_SHA"
    test "$(cat .deploy-commit)" = "$EXPECTED_DEPLOY_COMMIT"
    printf 'deploy OK: %s\n' "$EXPECTED_DEPLOY_COMMIT"
fi
check_sha experiments/portable/equiv.sbatch 9bcbeb74385c563fcef6fd0b358db76cf8ea6b4f6238a48526cd982c96ea77dc
check_sha experiments/portable/perfil.sh 722752beff83e18098988bbde754dfd5905feb8f93d00f5f70c1555c22fb1d67
check_sha clusters/perfiles/xula4.env 07324486a8be1bcc4aeaf12e8e60924ed7518751b36e551620aba2a47e6ef99e
check_sha discovery/collect_node.py 2c743b218d8ccbd6dd7789de6b48391c4176462f16776ab2608e5ebe4477b345
check_sha discovery/fingerprint.py c1198e22e43e5f9dab34a14873586ae6c04f54d7d18d959e586eb70eddf7f79c
check_sha instrumentation/cmdlog.sh 24077987874075fd47df1c3f44626265665ad25153da2928a2a2438753767c63
check_sha instrumentation/level1_capture.sh b0754484d7ddc4dc7c7f7e986564bc5c481f9330a06baa977c64f8cb3d96664d
export PERFIL=clusters/perfiles/xula4.env
# shellcheck source=/dev/null
source experiments/portable/perfil.sh
PYTHON=python3
[ "${DRY_RUN:-0}" = 1 ] || PYTHON=$PYTHON_DISCOVERY
"$PYTHON" -I -c '
import hashlib
from pathlib import Path
ps = sorted(Path("data/raw/xula/fase1/discovery").glob("*.json"))
assert len(ps) == 22
actual = hashlib.sha256("".join(p.name + ":" + hashlib.sha256(p.read_bytes()).hexdigest() + "\n" for p in ps).encode()).hexdigest()
assert actual == "a1adce082881af0e133430388f6ae1dcc1315dcb16f623329c657e7fd75a1761", "JSON de referencia distintos"
print("sha256 OK: 22 JSON de descubrimiento")
'
EXCLUDE=xula5001,xula5002,xula5202,xula5403,xula5404,xula5603
COMMON=(--parsable --exclusive --partition=xula4 --qos=a --nodes=2
    --ntasks-per-node=1 --cpus-per-task=112 --time=00:20:00 "--exclude=$EXCLUDE")
[ -z "$ACCOUNT" ] || COMMON+=("--account=$ACCOUNT")
if [ "${DRY_RUN:-0}" = 1 ]; then
    dry_sbatch() { printf 'DRY_RUN sbatch'; printf ' %q' "$@"; printf '\n'; }
    # El identificador es solo marcador; no se ejecuta sbatch.
    dry_sbatch "${COMMON[@]}" --output=data/raw/xula/equivalence/humo-%j.out experiments/portable/equiv.sbatch humo
    HUMO=900000
else
    mkdir -p data/raw/xula/equivalence
    HUMO=$(sbatch "${COMMON[@]}" --output=data/raw/xula/equivalence/humo-%j.out experiments/portable/equiv.sbatch humo)
    HUMO=${HUMO%%;*}
    [[ "$HUMO" =~ ^[0-9]+$ ]] || exit 5
    printf 'humo=%s\n' "$HUMO"
fi
COMMON+=("--dependency=afterok:$HUMO" --kill-on-invalid-dep=yes "--export=ALL,EQUIV_SMOKE_JOB=$HUMO" --output=data/raw/xula/equivalence/medida-%j.out)
SEND=(sbatch)
[ "${DRY_RUN:-0}" != 1 ] || SEND=(dry_sbatch)
# Una línea de envío por medida; un error detiene los envíos restantes, sin cancelar.
"${SEND[@]}" "${COMMON[@]}" experiments/portable/equiv.sbatch medida
"${SEND[@]}" "${COMMON[@]}" experiments/portable/equiv.sbatch medida
"${SEND[@]}" "${COMMON[@]}" experiments/portable/equiv.sbatch medida
"${SEND[@]}" "${COMMON[@]}" experiments/portable/equiv.sbatch medida
"${SEND[@]}" "${COMMON[@]}" experiments/portable/equiv.sbatch medida
"${SEND[@]}" "${COMMON[@]}" experiments/portable/equiv.sbatch medida
"${SEND[@]}" "${COMMON[@]}" experiments/portable/equiv.sbatch medida
"${SEND[@]}" "${COMMON[@]}" experiments/portable/equiv.sbatch medida
"${SEND[@]}" "${COMMON[@]}" experiments/portable/equiv.sbatch medida
"${SEND[@]}" "${COMMON[@]}" experiments/portable/equiv.sbatch medida
"${SEND[@]}" "${COMMON[@]}" experiments/portable/equiv.sbatch medida
"${SEND[@]}" "${COMMON[@]}" experiments/portable/equiv.sbatch medida
"${SEND[@]}" "${COMMON[@]}" experiments/portable/equiv.sbatch medida
"${SEND[@]}" "${COMMON[@]}" experiments/portable/equiv.sbatch medida
"${SEND[@]}" "${COMMON[@]}" experiments/portable/equiv.sbatch medida
