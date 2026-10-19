#!/usr/bin/env bash
# L14b — T19: E-d cpu36c, controles D-B limpios, acotados y no bloqueantes.
# Objetivo: FT D, 8 nodos x 32 ranks = 256; binarios GCC/intelc CLX.
# Autoriza: informes/ordenes/2026-10-14-T19-ed-cpu36c.md;
# informes/ordenes/2026-10-15-T19-L14b.md; DEVIATIONS 2026-10-15 T19.
# Resolución: informes/ordenes/2026-10-15-T19-L14b-escalada.md.
# DEVIATIONS 2026-10-14 T19, E-d 2026-10-04/05, R1 y R14.
# Scripts en commit 280e3c4290612d69319c3ce6f6a79c9b5178cb84:
#   experiments/ed_ft36-v2.sbatch
#   instrumentation/cmdlog.sh
#   instrumentation/level1_capture.sh
# Sus hashes quedan fijados en check_sha, antes del primer sbatch (regla 9).
# Nodos: 8 cualesquiera de cpu36c, --exclusive, sin reserva ni nodelist.
# Ingenuo: sin --exclude ni opciones MPI de mapping/binding.
# Recomendado: intelc/mlx, CPUs 0-15,18-33, sin aac108,aac111,acc111.
# Jobs: 2 humos x 1 ronda, 00:15:00/job; 8 medidas x 11 rondas,
# 00:30:00/job. Máximo solicitado: (2x15+8x30)/60 x 8 = 36 nodo-hora.
# FT: 90 runs (2 humo + 88 medida); 80 efectivos (10/asignación).
# D-B: 10 controles (2 por cada una de las 5 asignaciones recomendadas).
# Manifiestos: humo I=1, humo R=3; cada medida I=11, R=13 filas de datos.
# Orden: I1→R1→I2→R2→I3→R3→I4→R4; afterany entre medidas, como L1-v2.
# TODAS las medidas requieren afterok de AMBOS humos y kill-on-invalid-dep.
# QA a: humos reales 8x32, aún pendientes de firma y ejecución.
# QA b: nodos/SMT, map-check por run, ldd por nodo; mlx/mapa del FT recomendado.
#       Ingenuo conserva la selección de transporte por defecto, sin imponer par.
# QA c: SUCCESSFUL + clase/tamaño D + 256; negativo derivado de cada log real.
# QA d: exit real registrado; QA/FT bloqueantes; control FALLO no bloqueante.
#       D-B: env -i, login sin nounset, GCC/UCX y timeout -k 30 300 por control.
# QA e: parámetros trazados a la orden y desviación anterior; CLX como L3-v3.
# QA f: excepción LITERAL autorizada: no revisión humana entre humo y medida.
# QA g: tras cada job, sync inmutable de cc/raw/infrautil/ed36-<modo>-<job>/,
#       más data/raw/infrautil/<nombre>-<job>.out; verificar hashes/manifiesto
#       y anotarlo en el panel (PROCEDIMIENTOS 6). No ejecutado en preparación.
#       Tras firma: sacct cada 15 min hasta sábado 17 a las 12:00; sin análisis.
# QA h: fichero versionado; la persona firma su sha256 COMPLETO por mensaje.
# NO ejecutarlo sin esa firma. Hash y aprobación se registran fuera del fichero.
# Ejecución tras firma/despliegue: exportar TURGALIUM_REPO en la sesión remota,
# y ejecutar este fichero TAL CUAL con bash, desde su checkout (reglas 3/9).
set -euo pipefail
REPO="${TURGALIUM_REPO:?exportar TURGALIUM_REPO antes de ejecutar L14b}"
cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="280e3c4290612d69319c3ce6f6a79c9b5178cb84"
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
check_sha experiments/ed_ft36-v2.sbatch 6512a383d9a8842bc2951b0dd64ef343698b7eed4b6fd3fda51efa865d23117f
check_sha instrumentation/cmdlog.sh 24077987874075fd47df1c3f44626265665ad25153da2928a2a2438753767c63
check_sha instrumentation/level1_capture.sh b0754484d7ddc4dc7c7f7e986564bc5c481f9330a06baa977c64f8cb3d96664d
mkdir -p data/raw/infrautil
check_id() { [[ "$1" =~ ^[0-9]+$ ]] || { echo "!! job ID inválido: $1" >&2; exit 5; }; }

HI="$(sbatch --parsable --job-name=cc-ed36-humo-I --nodes=8 --time=00:15:00 experiments/ed_ft36-v2.sbatch ingenuo 1 1)"
HI="${HI%%;*}"; check_id "$HI"; echo "humo ingenuo=$HI"
HR="$(sbatch --parsable --job-name=cc-ed36-humo-R --nodes=8 --exclude=aac108,aac111,acc111 --time=00:15:00 experiments/ed_ft36-v2.sbatch recomendado 1 1)"
HR="${HR%%;*}"; check_id "$HR"; echo "humo recomendado=$HR"
SMOKE="afterok:$HI:$HR"
I1="$(sbatch --parsable --nodes=8 --time=00:30:00 --dependency="$SMOKE" --kill-on-invalid-dep=yes experiments/ed_ft36-v2.sbatch ingenuo 1 11)"
I1="${I1%%;*}"; check_id "$I1"; echo "I1=$I1"
R1="$(sbatch --parsable --nodes=8 --exclude=aac108,aac111,acc111 --time=00:30:00 --dependency="$SMOKE,afterany:$I1" --kill-on-invalid-dep=yes experiments/ed_ft36-v2.sbatch recomendado 1 11)"
R1="${R1%%;*}"; check_id "$R1"; echo "R1=$R1"
I2="$(sbatch --parsable --nodes=8 --time=00:30:00 --dependency="$SMOKE,afterany:$R1" --kill-on-invalid-dep=yes experiments/ed_ft36-v2.sbatch ingenuo 1 11)"
I2="${I2%%;*}"; check_id "$I2"; echo "I2=$I2"
R2="$(sbatch --parsable --nodes=8 --exclude=aac108,aac111,acc111 --time=00:30:00 --dependency="$SMOKE,afterany:$I2" --kill-on-invalid-dep=yes experiments/ed_ft36-v2.sbatch recomendado 1 11)"
R2="${R2%%;*}"; check_id "$R2"; echo "R2=$R2"
I3="$(sbatch --parsable --nodes=8 --time=00:30:00 --dependency="$SMOKE,afterany:$R2" --kill-on-invalid-dep=yes experiments/ed_ft36-v2.sbatch ingenuo 1 11)"
I3="${I3%%;*}"; check_id "$I3"; echo "I3=$I3"
R3="$(sbatch --parsable --nodes=8 --exclude=aac108,aac111,acc111 --time=00:30:00 --dependency="$SMOKE,afterany:$I3" --kill-on-invalid-dep=yes experiments/ed_ft36-v2.sbatch recomendado 1 11)"
R3="${R3%%;*}"; check_id "$R3"; echo "R3=$R3"
I4="$(sbatch --parsable --nodes=8 --time=00:30:00 --dependency="$SMOKE,afterany:$R3" --kill-on-invalid-dep=yes experiments/ed_ft36-v2.sbatch ingenuo 1 11)"
I4="${I4%%;*}"; check_id "$I4"; echo "I4=$I4"
R4="$(sbatch --parsable --nodes=8 --exclude=aac108,aac111,acc111 --time=00:30:00 --dependency="$SMOKE,afterany:$I4" --kill-on-invalid-dep=yes experiments/ed_ft36-v2.sbatch recomendado 1 11)"
R4="${R4%%;*}"; check_id "$R4"; echo "R4=$R4"
echo "L14b: humos=$HI,$HR I1=$I1 R1=$R1 I2=$I2 R2=$R2 I3=$I3 R3=$R3 I4=$I4 R4=$R4"
