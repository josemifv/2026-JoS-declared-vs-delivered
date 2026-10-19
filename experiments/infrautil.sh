#!/usr/bin/env bash
# Prueba de infrautilización: 1 nodo, STREAM solo gcc (D20), FT y EP con ambos
# stacks, 16/32/56/64 ranks, binding por defecto vs binding explícito (se delega en el
# runtime; la discrepancia de colocación ES el objeto de estudio, R10).
# Extensiones pre-registradas (DEVIATIONS 2026-09-30, SMT): además del nodo SMT-off de
# cpu112c, un nodo CON SMT de cpu112c (b9p02) y los representantes de cpu36c
# (aac102 SMT-off, acc101 SMT-on). EP añadido a los kernels.
# Ranks: cpu112c 16/32/56/64; cpu36c 16/32 (56/64 no caben en 36 cores: se omiten y
# se declaran; FT además exige potencia de 2, DEVIATIONS 2026-10-04).
#
# ESTRUCTURA (3ª auditoría, bloque C; REPS 10+1 decidido por la persona): UN job por
# nodo-grupo con TODOS los bucles dentro (pila × kernel × ranks × binding); los DOS
# jobs de cpu112c se lanzan EN PARALELO [O], y los dos de cpu36c igual — no un job
# por celda. Repeticiones: 11 por celda = 1 calentamiento + 10 efectivas (ronda 1 =
# calentamiento; misma convención R1 que el resto del estudio).
# v10 (T02, 2026-10-07): entorno LIMPIO por celda — run_cell corre en un SUBSHELL
# que hace unset de TODAS las variables de pin/afinidad antes de exportar las de
# su binding (83839-83842: las celdas Intel «default» heredaron
# I_MPI_PIN_PROCESSOR_LIST de la explícita anterior). Además:
# validar_sobresuscripcion (dos ranks/hilos con la misma CPU →
# FALLO-SOBRESUSCRIPCION, celda sin runs), validar_mapcheck exige nº de líneas
# cpus= = RANKS = longitud del mapa, y modo DRY_RUN=1 (sin mpirun/binarios/
# module/srun: imprime el entorno efectivo por celda; funciona en local con
# SLURM_JOB_ID=0).
# v9 (Prompt C, 2026-10-06): DESHACE la v8 — la base de D3 era un artefacto del
# fallo R/RANK de rank_wrap.sh (todos los ranks gcc explicit quedaron en la CPU 0:
# map-checks de 83871-83873); con binding por defecto FT D tarda 250-255 s a 16
# ranks y 156-158 s a 32 en cpu112c, y 282-353 s a 16 ranks en cpu36c. FT vuelve a
# la CLASE D (D19: binarios ft.D.x de fase B, verificados; 16/32/64 en b9p; 16/32
# en c36; 56 saltado por potencia de 2). Además: mapas b9p-on = los mismos que
# b9p-off (las CPU 112-167 son hermanos del paquete 0, no el paquete 1); la celda
# explicit solo es válida si su map-check coincide con el mapa pedido (FALLO-MAPA,
# P-E77); STREAM por defecto hace unset del affinity (no export vacío); STREAM
# registra OMP_DISPLAY_AFFINITY por celda y recompila con STREAM_ARRAY_SIZE=200000000
# (helpers/compile_stream_big.sbatch; regla 4x LLC de STREAM).
# v4 (auditorías 2026-10-05):
#   - REPS=11 (10+1, decisión de la persona; antes 3 PROPUESTAS sin entrada).
#   - Rutas STREAM REALES verificadas en scratch (2026-10-05): stream/<pila>/stream_spr
#     (sin subdir de arquitectura); los stream_clx de cpu36c NO existen aún: se
#     compilan con compile_stream.sbatch (línea pendiente de aprobación) y la celda
#     queda SIN-BINARIO en el manifiesto (no aborta el job).
#   - rankfile con sintaxis Open MPI/PRRTE "rank N=host slot=X" (la de v3 con ':'
#     no era válida) y nota de que slot es índice LÓGICO de hwloc; se valida con
#     map-check de la celda.
#   - map-check POR CELDA (colocación real registrada; es el objeto de la prueba).
#   - Validación del nodo asignado y su estado SMT por grupo (lscpu) + lanzamiento
#     con --nodelist explícito del representante del grupo.
#   - (v3) binarios por ARQUITECTURA — spr para b9p-*, clx para c36-*; verificación
#     POR KERNEL (el Size de FT D solo se exige a FT); partición VALIDADA por grupo;
#     mapa gcc aplicado de verdad vía rankfile; FT 56 rechazado (potencia de 2).
# Uso (crear el dir de salida ANTES: el .out lo abre slurmctld al enviar):
#   mkdir -p data/raw/infrautil
#   sbatch -p cpu112c --nodelist=b9p03 infrautil.sh b9p-off    # SMT-off cpu112c
#   sbatch -p cpu112c --nodelist=b9p02 infrautil.sh b9p-on     # SMT-on (o b9p12)
#   sbatch -p cpu36c  --nodelist=aac102 infrautil.sh c36-off   # representante cpu36c
#   sbatch -p cpu36c  --nodelist=acc101 infrautil.sh c36-on
#   2.º argumento opcional = reps (defecto 11; humo QA = 1):
#   sbatch -p cpu112c --nodelist=b9p03 infrautil.sh b9p-off 1
#   Los dos de cpu112c en paralelo [O]; los dos de cpu36c en paralelo [O].
#SBATCH --job-name=cc-infra
#SBATCH --exclusive
#SBATCH --partition=cpu112c
#SBATCH --nodes=1
#SBATCH --output=data/raw/infrautil/%x-%j.out
#SBATCH --time=03:30:00

set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}" || exit 1
DRY_RUN="${DRY_RUN:-0}"   # v10 (T02): 1 = sin mpirun/binarios/module/srun; local OK
if [ -f clusters/local.env ]; then
  source clusters/local.env
elif [ "$DRY_RUN" = 1 ]; then
  # v10 (T02) corrección (e): DRY_RUN sin local.env usa marcadores para que
  # el revisor pueda ejecutar C1 sin tener el fichero de configuración local
  TURGALIUM_SCRATCH="${TMPDIR:-/tmp}/infrautil-dry-mock"
  mkdir -p "$TURGALIUM_SCRATCH/benchmarks/npb/gcc/spr" \
           "$TURGALIUM_SCRATCH/benchmarks/stream/gcc" \
           "$TURGALIUM_SCRATCH/benchmarks/npb/intel/spr" 2>/dev/null || true
  TURGALIUM_REPO="$PWD"
else
  echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1
fi

GRUPO="${1:?uso: infrautil.sh <b9p-off|b9p-on|c36-off|c36-on> [reps]}"
case "$GRUPO" in
  b9p-*|c36-*) ;;
  *) echo "!! grupo desconocido: $GRUPO" >&2; exit 2 ;;
esac
REPS_ARG="${2:-11}"   # humo QA: 1
case "$REPS_ARG" in 1|11) ;; *) echo "!! reps solo 1 (humo) u 11 (medida)" >&2; exit 2 ;; esac
DRY_RUN="${DRY_RUN:-0}"   # v10 (T02): 1 = sin mpirun/binarios/module/srun; local OK
# Partición por grupo (v3): c36-* corre en cpu36c (en DRY_RUN no hay asignación)
if [ "$DRY_RUN" != 1 ]; then
  case "$GRUPO" in
    c36-*) [ "${SLURM_JOB_PARTITION:-}" = cpu36c ] || { echo "!! lanza los grupos c36-* con -p cpu36c" >&2; exit 2; } ;;
    b9p-*) [ "${SLURM_JOB_PARTITION:-}" = cpu112c ] || { echo "!! lanza los grupos b9p-* con -p cpu112c" >&2; exit 2; } ;;
  esac
fi

REPO_COMMIT="$(awk '{print $1}' .deploy-commit 2>/dev/null || true)"
# 3ª auditoría (1c): el despliegue escribe el hash COMPLETO de rev-parse HEAD;
# se valida el formato y, si no cumple, se cae al git del clon o a "desconocido"
echo "$REPO_COMMIT" | grep -qE '^[0-9a-f]{7,40}$' || REPO_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo 'desconocido (clon no alineado)')"
if [ "$DRY_RUN" = 1 ]; then
  # v10 (T02): entorno DRY — sin clúster ni scratch; el manifiesto va a temporal
  NODO="nodo-dry"; THREADS="dry"
  CMDLOG_DIR="${TMPDIR:-/tmp}/infrautil-dry-$$"
  CMDLOG_RUN_ID="infra-dry-$$"
  mkdir -p "$CMDLOG_DIR"
  module() { :; }   # stub: sin módulos en DRY_RUN
  srun()  { echo "nodo-dry"; }
  L1="/dev/null"    # bash /dev/null = no-op
  # v10 (T02): en local (macOS) no hay sha256sum del GNU; DRY_RUN usa shasum
  command -v sha256sum >/dev/null 2>&1 || sha256sum() { shasum -a 256 "$@"; }
else
  CMDLOG="$TURGALIUM_REPO/instrumentation/cmdlog.sh"
  L1="$TURGALIUM_REPO/instrumentation/level1_capture.sh"
  [ -x "$CMDLOG" ] && [ -f "$L1" ] || { echo "!! falta instrumentación" >&2; exit 3; }
  export LEVEL1_MODE="unprivileged"   # R14
  # Validación del nodo asignado y su SMT (bloque C): el grupo fija el estado esperado
  NODO="$(srun --ntasks=1 hostname -s)"
  THREADS="$(lscpu | awk '/Thread\(s\) per core/ {print $4}')"
  case "$GRUPO" in
    *-off) ESPERADO=1 ;;   # 1 hilo/core = SMT desactivado
    *-on)  ESPERADO=2 ;;   # 2 hilos/core = SMT activado
  esac
  [ "$THREADS" = "$ESPERADO" ] || { echo "!! $NODO tiene SMT=$THREADS hilos/core; $GRUPO exige SMT=$ESPERADO (usa el --nodelist del representante)" >&2; exit 3; }
  export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/infrautil/$GRUPO-$SLURM_JOB_ID"
  export CMDLOG_RUN_ID="infra-$GRUPO-$SLURM_JOB_ID"
  mkdir -p "$CMDLOG_DIR"
fi

REPS="$REPS_ARG"   # medida: 11 = 1 calentamiento + 10 efectivas (persona); humo: 1
# (FT 56 solo se recorre en b9p-*: ahí se declara SALTADA por potencia de 2)
DIMS_FT="2048x1024x1024"  # clase D de FT (D19, v9; verificación: SOLO ft; EP no lleva Size)
case "$GRUPO" in b9p-*) ARCH=spr ;; c36-*) ARCH=clx ;; esac   # v3: binarios por arq.

# Mapas explícitos: bloques consecutivos por paquete (patrón del 64 aprobado en fase
# B: 0-31,56-87). b9p-on: hipótesis hermano = i+112 (PROPUESTA; el mapa real queda
# registrado por run y su discrepancia se analiza — es el objeto de la prueba, R10).
MAPA_EXPLICITO() { # $1 = grupo; $2 = ranks → imprime la lista para I_MPI/OMPI o GOMP
  case "$1:$2" in
    b9p-off:16) echo "0-7,56-63" ;;
    b9p-off:32) echo "0-15,56-71" ;;
    b9p-off:56) echo "0-27,56-83" ;;
    b9p-off:64) echo "0-31,56-87" ;;
    # v9 (Prompt C): en b9p-on las CPU 112-167 son los hermanos SMT del PAQUETE 0
    # (lscpu del descubrimiento: "NUMA node0 CPU(s): 0-55,112-167" —
    # data/raw/discovery/turgalium/cpu112c/outputs/16883d99a2ea2152061a592e8acef498fbad9c1230eb5386b7a3e065d0f986ef.out:26,
    # nodo b9p02; ídem outputs/58eaf08d171f8ae388c2e19ed3554fc272c898040a5119d9c29f6440774fb420.out:26, b9p12).
    # Los mapas v1-v8 metían todos los ranks en el paquete 0, en hilos hermanos:
    # MISMOS mapas que b9p-off.
    b9p-on:16)  echo "0-7,56-63" ;;
    b9p-on:32)  echo "0-15,56-71" ;;
    b9p-on:56)  echo "0-27,56-83" ;;
    b9p-on:64)  echo "0-31,56-87" ;;
    c36-off:16|c36-on:16) echo "0-7,18-25" ;;
    c36-off:32|c36-on:32) echo "0-15,18-33" ;;
    *) echo "" ;;
  esac
}

# v7: el RANKFILE de Open MPI 5.0.5 es INUTILIZABLE dentro de asignaciones Slurm
# (humos 83732/83839-83842: -rf no reconocido; --rankfile y --map-by
# rankfile:file= acaban en rc=213 «host not allocated or oversubscribed» con el
# host correcto; en el login sí funciona — hallazgo declarado/real, DEVIATIONS).
# Binding gcc explicit = WRAPPER taskset por rank: el rank i se fija al cpu
# i-ésimo del mapa expandido (mismo mapa pedido que el rankfile, verificado por
# map-check R10; la herramienta cambia y se declara).
generar_cpus() { # $1 = mapa (rangos con comas); $2 = ranks; $3 = fichero (1 cpu/línea)
  local cpus=() r a b i
  for r in $(echo "$1" | tr ',' ' '); do
    if [[ "$r" == *-* ]]; then a="${r%-*}"; b="${r#*-}"; mapfile -t -O "${#cpus[@]}" cpus < <(seq "$a" "$b"); else cpus+=( "$r" ); fi
  done
  : > "$3"
  for i in $(seq 0 $(( $2 - 1 ))); do
    echo "${cpus[$i]}" >> "$3"
  done
}
RANK_WRAP="$CMDLOG_DIR/rank_wrap.sh"
cat > "$RANK_WRAP" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
# $1 = fichero cpu-por-rank; resto = comando a ejecutar en el rank
# v9 (Prompt C): sin OMPI_COMM_WORLD_RANK el wrapper ABORTA (exit 3). La v7
# asignaba R="${OMPI_COMM_WORLD_RANK:-0}" pero leía "$RANK" (SIN definir), de
# modo que sed -n "1p" daba SIEMPRE la primera CPU: todos los ranks gcc explicit
# en la CPU 0 (map-checks de 83871-83873; D19/P-E77).
[ -n "${OMPI_COMM_WORLD_RANK:-}" ] || { echo "!! rank_wrap: OMPI_COMM_WORLD_RANK sin definir" >&2; exit 3; }
R="$OMPI_COMM_WORLD_RANK"
CPU="$(sed -n "$(( R + 1 ))p" "$1")"
[ -n "$CPU" ] || { echo "!! rank_wrap: sin CPU para el rank $R en $1" >&2; exit 3; }
shift
exec taskset -c "$CPU" "$@"
EOF
chmod +x "$RANK_WRAP"

# v9 (Prompt C, 3.4): validación del map-check de la celda (QA b). Una celda
# explicit solo es válida si el mapa REAL coincide con el pedido:
#   gcc:   rank i → CPU i-ésima del mapa expandido;
#   intel: conjunto de CPUs observado = mapa expandido Y cada rank con UNA CPU.
# Devuelve 0 = OK; 1 = FALLO-MAPA. Probada localmente (QA e): positivo sintético y
# negativo data/raw/infrautil/b9p-off-83871/mapcheck-gcc-ft-16-explicit.txt.
expandir_mapa() { # $1 = mapa (rangos con comas) → una cpu por línea
  local r a b
  for r in $(echo "$1" | tr ',' ' '); do
    if [[ "$r" == *-* ]]; then a="${r%-*}"; b="${r#*-}"; seq "$a" "$b"; else echo "$r"; fi
  done
}
validar_mapcheck() { # $1 = pila (gcc|intel); $2 = mapa pedido; $3 = fichero map-check
  local pila="$1" mapa="$2" f="$3" nr pairs rank cpu exp set_exp set_obs
  [ -s "$f" ] || return 1
  nr="$(grep -c 'cpus=' "$f" 2>/dev/null || true)"
  [ "${nr:-0}" -gt 0 ] || return 1
  # cada rank exactamente UNA cpu (las líneas terminan en cpus=<numero>)
  [ "$(grep 'cpus=' "$f" | grep -cvE '.*rank=[0-9]+.*cpus=[0-9]+ *$')" = 0 ] || return 1
  pairs="$(grep 'cpus=' "$f" | sed -E 's/.*rank=([0-9]+).*cpus=([0-9]+).*/\1 \2/' | sort -n)"
  [ "$(echo "$pairs" | wc -l | tr -d ' ')" = "$nr" ] || return 1
  # v10 (T02): nº de ranks observados = RANKS = longitud del mapa expandido
  [ "$nr" = "${RANKS:-}" ] || return 1
  [ "$nr" = "$(expandir_mapa "$mapa" | wc -l | tr -d ' ')" ] || return 1
  if [ "$pila" = gcc ]; then
    while read -r rank cpu; do
      [ -n "$rank" ] || continue
      exp="$(expandir_mapa "$mapa" | sed -n "$(( rank + 1 ))p")"
      [ "$cpu" = "$exp" ] || return 1
    done <<< "$pairs"
  else
    set_exp="$(expandir_mapa "$mapa" | sort -n | tr '\n' ',')"
    set_obs="$(echo "$pairs" | awk '{print $2}' | sort -n | tr '\n' ',')"
    [ "${set_obs%,}" = "${set_exp%,}" ] || return 1
  fi
  return 0
}
# T03: validación del map-check de STREAM explicit (hilos OpenMP).
# libgomp produce el formato pedido por OMP_AFFINITY_FORMAT:
# «thread=<n> cpus=<cpu>». Se exige un hilo por rank y la CPU esperada
# para cada número de hilo según el mapa solicitado.
validar_mapcheck_omp() { # $1 = mapa pedido; $2 = fichero map-check
  local mapa="$1" f="$2" nth thr cpus exp expected
  [ -s "$f" ] || return 1
  expected="${RANKS:-}"
  [ -n "$expected" ] || return 1
  nth="$(grep -cE '^thread=[0-9]+[[:space:]]+cpus=[0-9]+$' "$f" 2>/dev/null || true)"
  [ "$nth" = "$expected" ] || return 1
  while read -r thr cpus; do
    exp="$(expandir_mapa "$mapa" | sed -n "$(( thr + 1 ))p")"
    [ -n "$exp" ] && [ "$cpus" = "$exp" ] || return 1
  done < <(grep -E '^thread=[0-9]+[[:space:]]+cpus=[0-9]+$' "$f" | sed -E 's/^thread=([0-9]+)[[:space:]]+cpus=([0-9]+)$/\1 \2/')
  return 0
}

# v10 (T02): dos ranks o hilos con la misma CPU única = sobresuscripción no
# declarada (83839-83842: 32 ranks en 16/8 CPUs). Aplica a todas las celdas,
# por defecto y explícitas. → 0 OK; 1 FALLO-SOBRESUSCRIPCION.
# Solo cuentan CPUs ÚNICAS: «cpus=<n>» de UN número y conjuntos OMP de un
# número; rangos y listas (p. ej. los cpus=0-6 del default de Intel en el
# ft-16 de 83839) no declaran una CPU única y no se juzgan aquí.
validar_sobresuscripcion() { # $1 = fichero map-check
  local f="$1" dups
  [ -s "$f" ] || return 1
  dups="$( { grep -E 'cpus=[0-9]+ *$' "$f" | sed -E 's/.*cpus=([0-9]+) *$/\1/';
             grep -ioE 'bound to os proc set +\{[ ]*[0-9]+[ ]*\}' "$f" | grep -oE '[0-9]+'; } | sort -n | uniq -d)"
  [ -z "$dups" ]
}

# v10 (T02, revisión 3): etiqueta de la celda a partir de su map-check.
# Precedencia: map-check vacío o mapa real ≠ pedido (solo explicit) → FALLO-MAPA;
# si no, CPU única repetida → FALLO-SOBRESUSCRIPCION; si no, OK. La usa run_cell
# y la carga tests/test_infrautil.sh: la precedencia se prueba con el código real.
etiqueta_celda() { # $1 pila; $2 mapa; $3 binding; $4 fichero map-check
  local pila="$1" mapa="$2" binding="$3" f="$4"
  if [ ! -s "$f" ]; then echo FALLO-MAPA; return 0; fi
  if [ "$binding" = explicit ] && ! validar_mapcheck "$pila" "$mapa" "$f"; then
    echo FALLO-MAPA; return 0
  fi
  if ! validar_sobresuscripcion "$f"; then echo FALLO-SOBRESUSCRIPCION; return 0; fi
  echo OK
}

# v10 (T02): línea de entorno efectivo por celda en DRY_RUN
imprime_entorno_dry() {
  echo "pila=$STACK bench=$BENCH ranks=$RANKS binding=$BINDING I_MPI_PIN=${I_MPI_PIN-<unset>} I_MPI_PIN_PROCESSOR_LIST=${I_MPI_PIN_PROCESSOR_LIST-<unset>} GOMP_CPU_AFFINITY=${GOMP_CPU_AFFINITY-<unset>} KMP_AFFINITY=${KMP_AFFINITY-<unset>} OMP_PROC_BIND=${OMP_PROC_BIND-<unset>} bin=$BIN"
}

MAPCHECK='echo "$(hostname -s) rank=${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-${SLURM_PROCID:-NA}}} cpus=$(taskset -pc $$ | awk "{print \$NF}")"'

MANIFEST="$CMDLOG_DIR/manifest.csv"
echo "job,grupo,pila,kernel,ranks,binding,ronda,exit_code,verificacion,runlog" > "$MANIFEST"

# v10 (T02): «date -Is» es de GNU; en el bash/macOS local cae a «date» sin error
# (en el clúster, GNU date imprime el ISO como siempre)
FECHA="$(date -Is 2>/dev/null || date)"
echo "== infrautil job=$SLURM_JOB_ID $GRUPO nodo=$NODO SMT=$THREADS hilo(s)/core sha=$(sha256sum "$(readlink -f "$0")" | awk '{print $1}') $FECHA"
echo "== commit(desplegado): $REPO_COMMIT"

saltar_celda() { # $1 = etiqueta de verificación; $2 = motivo — declara la celda sin correrla
  local r
  for r in $(seq 1 "$REPS"); do
    echo "$SLURM_JOB_ID,$GRUPO,$STACK,$BENCH,$RANKS,$BINDING,$r,0,$1,-" >> "$MANIFEST"
  done
  echo "!! celda $STACK/$BENCH/$RANKS/$BINDING: $2 (declarada en el manifiesto)" >&2
}

run_cell() { # usa STACK BENCH RANKS BINDING del bucle
  local r RD ec v BIN
  MAP="$(MAPA_EXPLICITO "$GRUPO" "$RANKS")"
  if [ "$BINDING" = explicit ] && [ -z "$MAP" ]; then
    saltar_celda SALTADA "sin mapa para $GRUPO/$RANKS"; return 0
  fi
  # v10 (T02): entorno LIMPIO por celda — unset de TODAS las variables de pin y
  # afinidad ANTES de exportar las que pide el binding de esta celda (83839-83842:
  # las celdas intel «default» heredaron I_MPI_PIN_PROCESSOR_LIST de la explicit
  # anterior). La llamada va en un SUBSHELL (ver el bucle): nada de aquí contamina
  # la celda siguiente.
  unset I_MPI_PIN I_MPI_PIN_PROCESSOR_LIST I_MPI_PIN_DOMAIN \
        GOMP_CPU_AFFINITY KMP_AFFINITY OMP_PROC_BIND OMP_PLACES \
        OMP_DISPLAY_AFFINITY OMP_AFFINITY_FORMAT
  case "$BENCH" in
    stream)
      # T04/D20: gcc/libgomp, binario grande independiente del de fase B.
      BIN="$TURGALIUM_SCRATCH/benchmarks/stream/gcc/stream_${ARCH}_200M"
      export OMP_NUM_THREADS="$RANKS"
      if [ "$BINDING" = explicit ]; then
        export GOMP_CPU_AFFINITY="$MAP"
      fi
      # v10 (T02): en DRY_RUN no se ejecuta nada (ni binarios ni map-check):
      # solo se declara el entorno efectivo de la celda
      if [ "$DRY_RUN" = 1 ]; then imprime_entorno_dry; return 0; fi
      if [ ! -x "$BIN" ]; then
        saltar_celda SIN-BINARIO "falta $BIN (STREAM $ARCH: compilar con compile_stream_big.sbatch, v9)"; return 0
      fi
      # v9 (Prompt C, 3.6): colocación real de los HILOS OpenMP por celda (QA b);
      # binario con STREAM_ARRAY_SIZE=200000000 (regla 4x LLC). La salida de
      # afinidad queda en mapcheck-<pila>-stream-<ranks>-<binding>.txt.
      local MC_S
      MC_S="$CMDLOG_DIR/mapcheck-$STACK-stream-$RANKS-$BINDING.txt"
      export OMP_DISPLAY_AFFINITY=TRUE OMP_AFFINITY_FORMAT="thread=%n cpus=%A"
      OMP_NUM_THREADS="$RANKS" "$BIN" > "$MC_S" 2>&1 \
        || echo "!! map-check STREAM FALLO $STACK/$RANKS/$BINDING (conservado)"
      echo "--- map-check stream $STACK/$RANKS/$BINDING: $(grep -cE '^thread=[0-9]+[[:space:]]+cpus=' "$MC_S" || echo 0) hilos con afinidad registrada"
      if [ "$BINDING" = explicit ] && ! validar_mapcheck_omp "$MAP" "$MC_S"; then
        saltar_celda FALLO-MAPA "los hilos OMP no casan con el mapa pedido (map-check de celda)"
        return 0
      fi
      # v10 (T02): sobresuscripción en TODAS las celdas (default y explicit)
      if ! validar_sobresuscripcion "$MC_S"; then
        saltar_celda FALLO-SOBRESUSCRIPCION "hilos OMP comparten una CPU única (map-check de celda)"
        return 0
      fi
      for r in $(seq 1 "$REPS"); do
        RD="$CMDLOG_DIR/$STACK-$BENCH-$RANKS-$BINDING-r$(( 10#$r ))"; mkdir -p "$RD"
        echo "--- RUN stream $STACK ranks=$RANKS binding=$BINDING ronda=$r$([ "$r" = 1 ] && echo ' (calentamiento)')"
        if bash "$CMDLOG" "$BIN" > "$RD/run.log" 2>&1; then ec=0; else ec=$?; fi
        if [ "$ec" -eq 0 ] && grep -q "Solution Validates:" "$RD/run.log"; then v=VALIDA; else v=FALLO; fi
        echo "$SLURM_JOB_ID,$GRUPO,$STACK,$BENCH,$RANKS,$BINDING,$r,$ec,$v,$RD/run.log" >> "$MANIFEST"
      done ;;
    ft|ep)
      BIN="$TURGALIUM_SCRATCH/benchmarks/npb/$STACK/$ARCH/$BENCH.D.x"   # v9 (D19): clase D de nuevo; v3: arq. por grupo
      if [ "$DRY_RUN" != 1 ] && [ ! -x "$BIN" ]; then
        saltar_celda SIN-BINARIO "falta $BIN"; return 0
      fi
      # v10 (T02): primero el ENTORNO del binding (lo que imprime DRY_RUN)…
      case "$STACK:$BINDING" in
        intel:explicit) export I_MPI_PIN=1 I_MPI_PIN_PROCESSOR_LIST="$MAP" ;;
      esac
      # v10 (T02): …en DRY_RUN no se ejecuta mpirun ni se construye el lanzamiento
      # (generar_cpus usa mapfile, que no existe en el bash 3.2 de macOS): DRY_RUN
      # debe funcionar en local (C1 de T02)
      if [ "$DRY_RUN" = 1 ]; then imprime_entorno_dry; return 0; fi
      # …y después el LANZAMIENTO, que DRY_RUN no ejecuta
      case "$STACK:$BINDING" in
        gcc:default)    LAUNCH=(mpirun -np "$RANKS") ;;
        gcc:explicit)   CF="$CMDLOG_DIR/cpus-$STACK-$BENCH-$RANKS.txt"   # v7: taskset
                        generar_cpus "$MAP" "$RANKS" "$CF"               # 1 cpu por rank
                        LAUNCH=(mpirun -np "$RANKS" --bind-to none bash "$RANK_WRAP" "$CF") ;;
        intel:*)        LAUNCH=(mpirun -n "$RANKS" -ppn "$RANKS") ;;
      esac
      # map-check POR CELDA (bloque C): la colocación real, con el LAUNCH de la celda
      echo "--- map-check $STACK/$BENCH/$RANKS/$BINDING"
      local MC MAP_OK=1 FALLO_CELDA=""
      MC="$CMDLOG_DIR/mapcheck-$STACK-$BENCH-$RANKS-$BINDING.txt"
      "${LAUNCH[@]}" bash -c "$MAPCHECK" > "$MC" 2>&1 \
        || echo "!! map-check FALLO $STACK/$BENCH/$RANKS/$BINDING (conservado)"
      echo "    ranks con cpus=: $(grep -c 'cpus=' "$MC" || echo 0)"
      # v9 (Prompt C, 3.4, QA b): la celda explicit solo corre si el mapa REAL =
      # pedido (fallo rank_wrap de 83871-83873: cpus=0 y celdas dadas por válidas)
      # v10 (T02): FALLO-MAPA / FALLO-SOBRESUSCRIPCION / OK con la precedencia
      # de etiqueta_celda (P-E77 para el mapa; 83839-83842 para la sobresuscripción)
      FALLO_CELDA="$(etiqueta_celda "$STACK" "$MAP" "$BINDING" "$MC")"
      if [ "$FALLO_CELDA" = OK ]; then
        FALLO_CELDA=""
        echo "    map-check ($BINDING): OK (mapa y sobresuscripción)"
      else
        MAP_OK=0
        echo "!! $FALLO_CELDA $STACK/$BENCH/$RANKS/$BINDING (celda sin runs)"
      fi
      for r in $(seq 1 "$REPS"); do
        RD="$CMDLOG_DIR/$STACK-$BENCH-$RANKS-$BINDING-r$(( 10#$r ))"; mkdir -p "$RD"
        if [ "$MAP_OK" = 0 ]; then
          echo "$SLURM_JOB_ID,$GRUPO,$STACK,$BENCH,$RANKS,$BINDING,$r,0,${FALLO_CELDA:-FALLO-MAPA},-" >> "$MANIFEST"
          continue
        fi
        echo "--- RUN $BENCH $STACK ranks=$RANKS binding=$BINDING ronda=$r$([ "$r" = 1 ] && echo ' (calentamiento)')"
        if bash "$CMDLOG" "${LAUNCH[@]}" "$BIN" > "$RD/run.log" 2>&1; then ec=0; else ec=$?; fi
        # v3: verificación POR KERNEL — el Size de clase D solo se exige a FT (EP no
        # imprime 2048x1024x1024 y todas sus celdas caían en FALLO)
        if [ "$ec" -eq 0 ] && grep -qE "Verification[[:space:]]*=[[:space:]]*SUCCESSFUL" "$RD/run.log" \
           && { [ "$BENCH" = ep ] || grep -q "Size.*${DIMS_FT}" "$RD/run.log"; }; then v=SUCCESSFUL; else v=FALLO; fi
        echo "$SLURM_JOB_ID,$GRUPO,$STACK,$BENCH,$RANKS,$BINDING,$r,$ec,$v,$RD/run.log" >> "$MANIFEST"
      done ;;
    *) echo "!! bench desconocido: $BENCH (stream|ft|ep)" >&2; exit 2 ;;
  esac
}

bash "$L1" start
bash "$L1" pre
for STACK in gcc intel; do
  case "$STACK" in
    gcc)   module purge 2>/dev/null || true; module load openmpi_gcc/5.0.5 ucx/1.9.0 ;;
    intel) module purge 2>/dev/null || true; module load intel/2025.3.2 ;;
  esac
  module list > "$CMDLOG_DIR/modules-$STACK.txt" 2>&1 || true
  for BENCH in stream ft ep; do
    # D20: no se mide STREAM bajo Intel MPI (el mismo gcc/libgomp).
    if [ "$BENCH" = stream ] && [ "$STACK" = intel ]; then continue; fi
    case "$GRUPO" in
      # v5: en cpu36c TODOS los kernels van a 16/32 (56/64 no caben en 36 cores: se
      # omiten y se declaran, DEVIATIONS 2026-09-30 SMT); el humo 83731 corrió STREAM
      # 56/64 sobresuscrito (VALIDA) — filas fuera de diseño que se retiran.
      c36-*) RANKS_LIST="16 32" ;;
      *)     RANKS_LIST="16 32 56 64" ;;
    esac
    for RANKS in $RANKS_LIST; do
      # FT exige número de procesos potencia de 2 (DEVIATIONS 2026-10-04): 56 no vale
      if [ "$BENCH" = ft ] && [ "$RANKS" = 56 ]; then
        BINDING=default; saltar_celda SALTADA "FT exige potencia de 2 (DEVIATIONS 2026-10-04)"
        BINDING=explicit; saltar_celda SALTADA "FT exige potencia de 2 (DEVIATIONS 2026-10-04)"
        continue
      fi
      for BINDING in default explicit; do
        ( run_cell )   # v10 (T02): SUBSHELL — el unset/export de la celda no contamina la siguiente
      done
    done
  done
done
bash "$L1" post
bash "$L1" stop
VALIDADOR="$TURGALIUM_REPO/experiments/lib/valida_job.sh"
if bash "$VALIDADOR" "$(dirname "$MANIFEST")"; then
  :
else
  case "$?" in
    1) echo "VEREDICTO: REVISAR" ;;
    *) echo "VALIDADOR-NO-EJECUTADO" ;;
  esac
fi
echo "== infrautil $GRUPO terminado (job $SLURM_JOB_ID) $(date -Is 2>/dev/null || date) — $MANIFEST"
