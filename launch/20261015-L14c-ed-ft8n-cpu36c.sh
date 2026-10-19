#!/usr/bin/env bash
# L14c — T19: medir CUELGUE del lanzador por defecto sin abortar el job.
# Objetivo: FT D, 8 nodos x 32 ranks = 256; binarios GCC/intelc CLX.
# Autoriza: informes/ordenes/2026-10-15-T19-L14c.md;
# DEVIATIONS 2026-10-15 T19 L14c y órdenes históricas de L14/L14b.
# Scripts en commit 77b092baa962d739d3dedc38fecc01f9764a7796:
#   experiments/ed_ft36-v3.sbatch
#   instrumentation/cmdlog.sh
#   instrumentation/level1_capture.sh
# Sus hashes quedan fijados en check_sha, antes del primer sbatch (regla 9).
# Nodos: 8 cualesquiera de cpu36c, --exclusive, sin reserva ni nodelist.
# Ingenuo: sin --exclude ni opciones MPI de mapping/binding.
# Recomendado: intelc/mlx, CPUs 0-15,18-33, sin aac108,aac111,acc111.
# Jobs: 2 humos x 1 ronda, 00:20:00/job; 8 medidas x 6 rondas (1 + 5).
# Medidas: ingenuo 00:45:00/job, recomendado 00:30:00/job.
# Máximo solicitado: 8x(2x20+4x45+4x30)/60 = 45 1/3 nodo-hora (45 h 20 min).
# Hasta 50 FT (2 humo + 48 medida), 40 efectivos si no hay CUELGUE.
# D-B: 10 controles (2 por cada una de las 5 asignaciones recomendadas).
# Manifiesto por intento: mapcheck y FT, con duration_ms y exit reales.
# Sin cuelgues: humo I=2, R=4; medida I=12, R=14 filas de datos.
# Mapcheck CUELGUE: no hay FT en esa ronda; no se repone ninguna ronda.
# MPI: mapcheck timeout -k 30 120; FT timeout -k 30 240, ambos modos.
# 124/137 = CUELGUE no bloqueante. FT incorrecto/mapa recomendado bloqueantes.
# Los tiempos Slurm son los ordenados; 30 min no cubren toda combinación
# teórica de cuelgues repetidos y controles de hasta 330 s cada uno.
# Orden: I1→R1→I2→R2→I3→R3→I4→R4; afterany entre medidas, como L14b.
# TODAS las medidas requieren afterok de AMBOS humos y kill-on-invalid-dep.
# QA a: humos reales 8x32, aún pendientes de firma y ejecución.
# QA b: nodos/SMT, map-check por run, ldd por nodo; mlx/mapa del FT recomendado.
#       Mapa y transporte ingenuos observados, sin imponer proveedor ni binding.
# QA c: SUCCESSFUL + clase/tamaño D + 256; negativo derivado de cada FT terminado.
# QA d: exit/duración reales; CUELGUE conservado y siguiente ronda sin fallo.
#       D-B como v2: env -i, login sin nounset, timeout -k 30 300; no bloqueante.
# QA e: parámetros trazados a la orden L14c y su desviación; CLX como L3-v3.
# QA f: exceptuada por la orden; no revisión humana entre humo y medida.
# QA g: tras cada job, sync inmutable de cc/raw/infrautil/ed36-<modo>-<job>/,
#       más data/raw/infrautil/<nombre>-<job>.out; verificar hashes/manifiesto
#       y anotar en panel (PROCEDIMIENTOS 6). No ejecutado en preparación.
#       Tras firma: sacct cada 15 min hasta sábado 17 a las 12:00; sin análisis.
# QA h: fichero versionado; la persona firma su sha256 COMPLETO por mensaje.
# NO ejecutarlo sin esa firma. Hash y aprobación se registran fuera del fichero.
# Ejecución tras firma/despliegue: exportar TURGALIUM_REPO en la sesión remota,
# y ejecutar este fichero TAL CUAL con bash, desde su checkout (reglas 3/9).
set -euo pipefail
REPO="${TURGALIUM_REPO:?exportar TURGALIUM_REPO antes de ejecutar L14c}"
cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="77b092baa962d739d3dedc38fecc01f9764a7796"
ACTUAL="$(cat .deploy-commit)"
[[ "$ACTUAL" =~ ^[0-9a-f]{40}$ ]] || { echo "!! .deploy-commit inválido"; exit 4; }
if [ "$ACTUAL" != "$EXPECTED_COMMIT" ]; then
  echo "AVISO: despliegue $ACTUAL distinto del commit de scripts $EXPECTED_COMMIT; rigen SHA individuales."
fi
check_sha() {
  local real
  real="$(sha256sum "$1" | awk '{print $1}')"
  if [ "$real" != "$2" ]; then
    echo "!! SHA distinto: $1 esperado=$2 real=$real" >&2
    exit 4
  fi
  echo "sha256 OK: $1"
}
check_sha experiments/ed_ft36-v3.sbatch 8e59f514be3b83e3fcc74057179032ac24c37246e6dd4d15e848da4e865494d6
check_sha instrumentation/cmdlog.sh 24077987874075fd47df1c3f44626265665ad25153da2928a2a2438753767c63
check_sha instrumentation/level1_capture.sh b0754484d7ddc4dc7c7f7e986564bc5c481f9330a06baa977c64f8cb3d96664d
mkdir -p data/raw/infrautil
check_id() { [[ "$1" =~ ^[0-9]+$ ]] || { echo "!! job ID inválido: $1" >&2; exit 5; }; }

HI="$(sbatch --parsable --job-name=cc-ed36-humo-I --nodes=8 --time=00:20:00 experiments/ed_ft36-v3.sbatch ingenuo 1 1)"
HI="${HI%%;*}"; check_id "$HI"; echo "humo ingenuo=$HI"
HR="$(sbatch --parsable --job-name=cc-ed36-humo-R --nodes=8 --exclude=aac108,aac111,acc111 --time=00:20:00 experiments/ed_ft36-v3.sbatch recomendado 1 1)"
HR="${HR%%;*}"; check_id "$HR"; echo "humo recomendado=$HR"
SMOKE="afterok:$HI:$HR"
I1="$(sbatch --parsable --nodes=8 --time=00:45:00 --dependency="$SMOKE" --kill-on-invalid-dep=yes experiments/ed_ft36-v3.sbatch ingenuo 1 6)"
I1="${I1%%;*}"; check_id "$I1"; echo "I1=$I1"
R1="$(sbatch --parsable --nodes=8 --exclude=aac108,aac111,acc111 --time=00:30:00 --dependency="$SMOKE,afterany:$I1" --kill-on-invalid-dep=yes experiments/ed_ft36-v3.sbatch recomendado 1 6)"
R1="${R1%%;*}"; check_id "$R1"; echo "R1=$R1"
I2="$(sbatch --parsable --nodes=8 --time=00:45:00 --dependency="$SMOKE,afterany:$R1" --kill-on-invalid-dep=yes experiments/ed_ft36-v3.sbatch ingenuo 1 6)"
I2="${I2%%;*}"; check_id "$I2"; echo "I2=$I2"
R2="$(sbatch --parsable --nodes=8 --exclude=aac108,aac111,acc111 --time=00:30:00 --dependency="$SMOKE,afterany:$I2" --kill-on-invalid-dep=yes experiments/ed_ft36-v3.sbatch recomendado 1 6)"
R2="${R2%%;*}"; check_id "$R2"; echo "R2=$R2"
I3="$(sbatch --parsable --nodes=8 --time=00:45:00 --dependency="$SMOKE,afterany:$R2" --kill-on-invalid-dep=yes experiments/ed_ft36-v3.sbatch ingenuo 1 6)"
I3="${I3%%;*}"; check_id "$I3"; echo "I3=$I3"
R3="$(sbatch --parsable --nodes=8 --exclude=aac108,aac111,acc111 --time=00:30:00 --dependency="$SMOKE,afterany:$I3" --kill-on-invalid-dep=yes experiments/ed_ft36-v3.sbatch recomendado 1 6)"
R3="${R3%%;*}"; check_id "$R3"; echo "R3=$R3"
I4="$(sbatch --parsable --nodes=8 --time=00:45:00 --dependency="$SMOKE,afterany:$R3" --kill-on-invalid-dep=yes experiments/ed_ft36-v3.sbatch ingenuo 1 6)"
I4="${I4%%;*}"; check_id "$I4"; echo "I4=$I4"
R4="$(sbatch --parsable --nodes=8 --exclude=aac108,aac111,acc111 --time=00:30:00 --dependency="$SMOKE,afterany:$I4" --kill-on-invalid-dep=yes experiments/ed_ft36-v3.sbatch recomendado 1 6)"
R4="${R4%%;*}"; check_id "$R4"; echo "R4=$R4"
echo "L14c: humos=$HI,$HR I1=$I1 R1=$R1 I2=$I2 R2=$R2 I3=$I3 R3=$R3 I4=$I4 R4=$R4"
