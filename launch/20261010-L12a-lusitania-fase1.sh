#!/usr/bin/env bash
# T29 — L12a: fase 1 en Lusitania, exclusivamente lusitania.
# Autorización de preparación: informes/ordenes/2026-10-10-T29-T34.md,
# 2026-10-10-T29-desbloqueo.md y 2026-10-10-T29-C2.md. NO firma de lanzamiento.
# Scripts/perfil: commit 1221b4e4f4ef9196f97e60f06ea7ff5276602738; rigen SHA.
# Jobs: 35 discovery × 1 nodo × 00:20:00 = 11,666667 nodo-h;
# compila 1 × 01:00:00 = 1; verif 2 × 00:30:00 = 1;
# calib 8 × 00:45:00 = 6. Total 38 jobs, 19,666667 nodo-h reservadas <= 20.
# Límites preparados, no duraciones observadas. Tope global: 60 nodo-h reales,
# se contabiliza con sacct Elapsed × NNodes después de cada asignación (T31).
# Runs: 35 JSON discovery; 8 NPB compilados + 2 instalaciones OSU;
# verif: 1 OSU por transporte UCX/proveedor fi_info enumerado (cantidad dinámica);
# calib: 2 pilas × 2 clases FT × 1 ronda a 8 nodos = 4 runs (128 ranks).
# No decide R8: duración >=30 s en la talla mayor y memoria de un nodo.
# Sync T31: scratch/cc/raw/lusitania/fase1/ -> data/raw/lusitania/fase1/,
# incluidos manifests, commands.jsonl/outputs y logs Slurm/discovery; ignore-existing.
# Preparación local: DRY_RUN=1 bash launch/20261010-L12a-lusitania-fase1.sh.
# Ejecución SOLO con firma T31: bash launch/20261010-L12a-lusitania-fase1.sh.
# Usa ssh computaex 'bash -s'; bootstrap de ruta desde local.env, sin valor versionado.
# Alternativa desde checkout remoto: PORTABLE_REMOTE=1 bash launch/<este fichero>.
set -euo pipefail
if [ "${PORTABLE_REMOTE:-0}" != 1 ]; then
    LAUNCH_FILE="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    cd "$(dirname "$LAUNCH_FILE")/.."
    if [ "${DRY_RUN:-0}" != 1 ]; then
        [ -f clusters/local.env ] || { printf 'falta local.env\n' >&2; exit 2; }
        source clusters/local.env
        : "${LUSITANIA_REPO:?falta LUSITANIA_REPO}"
        {
            printf 'cd %q\nexport PORTABLE_REMOTE=1\n' "$LUSITANIA_REPO"
            cat "$LAUNCH_FILE"
        } | ssh computaex 'bash -s'
        exit "$?"
    fi
fi
check_sha() {
    local actual
    actual="$(sha256sum "$1" | awk '{print $1}')"
    [ "$actual" = "$2" ] || { printf 'sha256 MAL: %s\n' "$1" >&2; exit 4; }
    printf 'sha256 OK: %s\n' "$1"
}
check_sha clusters/perfiles/lusitania.env faf11b95cbb11f14aca1bbb0ba575f573b15778ab817d7fc203fadf6bff85b54
check_sha experiments/portable/perfil.sh fb17d0d5b6d1650a351f272e5ee949cbf64e4f243c27f2b00b9844d233fffaa2
check_sha experiments/portable/fase1.sh f72468fe8dbb3ee55ea8d852f393bb0766dbcef55764ca9b29c3ada6847d6577
check_sha experiments/portable/compila.sbatch fb3aabf1d44baa3ce08a2eecea5fdedce9a8e17d25f99393b7a09aa00c6323b7
check_sha experiments/portable/verif.sbatch bad1cbd6b5bb4864e92cb700605d854cab73454e93555178a1546f1a529438c2
check_sha experiments/portable/calib.sbatch dc062bd91aa12df8974522de663b9d7be04b6ef98cf3ec514335c8ea7fe8489d
check_sha experiments/portable/pin.sh 0874457ed4d699a897af9d292c489b353f99fab028d9f5402f35b8524cc7b355
check_sha experiments/portable/observa.py a24cecb043ba0fcd7a188b448492fb3820764da8a9dac606ceb97194ac253d79
check_sha discovery/run_discovery.sh a461371c0d4c6fe112a02c0d354a44fd4eea00429c848700b0ce9dc4920be2e0
check_sha discovery/collect_node.py 2c743b218d8ccbd6dd7789de6b48391c4176462f16776ab2608e5ebe4477b345
check_sha instrumentation/cmdlog.sh 24077987874075fd47df1c3f44626265665ad25153da2928a2a2438753767c63
export PERFIL=clusters/perfiles/lusitania.env
bash experiments/portable/fase1.sh
