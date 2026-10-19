#!/usr/bin/env bash
# Validador local de un job infrautil/ligero. No ejecuta benchmarks.
set -u

usage() { echo "uso: $0 [--salida <fichero>|-] <dir-del-job>" >&2; exit 2; }
OUTPUT=""
if [ "${1:-}" = --salida ]; then
  [ "$#" -eq 3 ] || usage
  OUTPUT="$2"
  [ -n "$OUTPUT" ] || usage
  shift 2
fi
[ "$#" -eq 1 ] || usage
JOBDIR="$1"
[ -d "$JOBDIR" ] || { echo "!! no existe el directorio: $JOBDIR" >&2; exit 2; }
MANIFEST="$JOBDIR/manifest.csv"
[ -f "$MANIFEST" ] || MANIFEST="$(find "$JOBDIR" -type f \( -name 'manifest.csv' -o -name 'ligero112-verif.csv' \) -print -quit 2>/dev/null)"
[ -n "${MANIFEST:-}" ] && [ -f "$MANIFEST" ] || { echo "!! falta manifest.csv/ligero112-verif.csv en $JOBDIR" >&2; exit 2; }

JOB="$(basename "$JOBDIR")"
OUTPUT="${OUTPUT:-$JOBDIR/validacion-$JOB.txt}"
TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
REPORT="$TMP/informe"
STATUS_FILE="$TMP/estados"
DURATION_FILE="$TMP/duraciones"
: > "$REPORT"
: > "$STATUS_FILE"
: > "$DURATION_FILE"
issues=0
alert=0
valid=0
cells=0
skipped=0
printf 'VALIDADOR DE JOB\njob: %s\nmanifiesto: %s\n' "$JOB" "$MANIFEST" >> "$REPORT"

# Los paths de runlog/mapcheck pueden ser absolutos del clúster; se resuelven
# primero tal cual y después por basename relativo al directorio sincronizado.
resolve_path() {
  local p="$1" base cell
  [ "$p" != "-" ] && [ -f "$p" ] && { printf '%s\n' "$p"; return; }
  base="$(basename "$p")"
  cell="$(basename "$(dirname "$p")")"
  find "$JOBDIR" -type f -path "*/$cell/$base" -print -quit 2>/dev/null || true
}
run_duration() {
  local p="$1" f
  f="$(resolve_path "$p")"
  [ -n "$f" ] || return 0
  awk -F= '/Time in seconds/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}' "$f"
}
map_file() {
  local run="$1" b stem
  b="$(basename "${run%/run.log}")"
  stem="${b%-r[0-9]*}"
  find "$JOBDIR" -type f \( -name "mapcheck-${b}.txt" -o -name "mapcheck-${stem}.txt" \) -print -quit 2>/dev/null
}

# infrautil.csv: job,grupo,pila,kernel,ranks,binding,ronda,exit_code,verificacion,runlog
header="$(head -n 1 "$MANIFEST")"
case "$header" in
  job,grupo,pila,kernel,ranks,binding,*|job,grupo,ronda,celda,par,ranks,exit_code,verificacion*|job,ronda,par,ranks,exit_code,verificacion*|pila,transporte,probe_exit,transporte_observado,coincide,veredicto) ;;
  *) echo "!! formato de manifiesto no reconocido: $MANIFEST" >&2; exit 2 ;;
esac
if printf '%s' "$header" | grep -q 'grupo,pila,kernel,ranks,binding'; then
  while IFS=, read -r job _grupo pila kernel ranks binding ronda ec verif runlog; do
    [ "$job" = job ] && continue
    [ -n "${job:-}" ] || continue
    case "$verif" in SALTADA*|SALTAADA*) skipped=$((skipped+1)); continue ;; esac
    cells=$((cells+1))
    key="$pila|$kernel|$ranks|$ronda"
    d="$(run_duration "$runlog")"
    [ -n "$d" ] && printf '%s|%s|%s\n' "$key" "$binding" "$d" >> "$DURATION_FILE"
    status="OK"
    if [ "$ec" != 0 ] || [[ "$verif" =~ ^(FALLO|SIN-BINARIO|FALLO-) ]]; then status=REVISAR; fi
    case "$verif" in FALLO-MAPA|FALLO-SOBRESUSCRIPCION)
      printf '%s: %s/%s/%s/%s (%s)\n' "$verif" "$pila" "$kernel" "$ranks" "$binding" "$runlog" >> "$REPORT" ;;
    esac
    mf="$(map_file "$runlog")"
    if [ "$binding" = explicit ] && [ -n "$mf" ]; then
      # Revalidar duplicados en el map-check; los fallos de correspondencia
      # declarados por infrautil se conservan desde el manifiesto.
      if grep -qE 'rank=[0-9]+ cpus=[0-9]+$' "$mf"; then
        dup="$(grep -oE 'cpus=[0-9]+$' "$mf" | sort | uniq -d | head -n 1)"
        [ -n "$dup" ] && { printf 'FALLO-MAPA: %s/%s/%s/%s (%s; %s)\n' "$pila" "$kernel" "$ranks" "$binding" "$runlog" "$mf" >> "$REPORT"; status=REVISAR; }
      fi
    fi
    if [ "$pila" = intel ] && [ -n "$mf" ]; then
      dup="$(grep -oE 'cpus=[0-9]+$' "$mf" | sort | uniq -d | head -n 1)"
      [ -n "$dup" ] && { printf 'FALLO-SOBRESUSCRIPCION: %s/%s/%s/%s (CPU %s; %s)\n' "$pila" "$kernel" "$ranks" "$binding" "${dup#cpus=}" "$mf" >> "$REPORT"; status=REVISAR; }
    fi
    if [ "$verif" = FALLO-PIN ]; then
      printf 'FALLO-PIN: %s/%s/%s/%s (%s)\n' "$pila" "$kernel" "$ranks" "$binding" "$runlog" >> "$REPORT"
      status=REVISAR
    fi
    if [ "$status" = OK ]; then valid=$((valid+1)); printf 'OK|%s\n' "$runlog" >> "$STATUS_FILE"; else issues=$((issues+1)); printf 'REVISAR|%s\n' "$runlog" >> "$STATUS_FILE"; fi
  done < "$MANIFEST"

  # Twin alert: mismo stack/kernel/ranks/ronda, binding opuesto, duración >3x o <1/3x.
  if [ -s "$DURATION_FILE" ]; then
    awk -F'|' '$5=="default" {d[$1 FS $2 FS $3 FS $4]=$6} $5=="explicit" {e[$1 FS $2 FS $3 FS $4]=$6} END {for (k in d) if (e[k] != "" && (d[k] > 3*e[k] || e[k] > 3*d[k])) printf "ALERTA-DURACION: %s|default y %s|explicit (%.2fs frente a %.2fs)\n", k, k, d[k], e[k]}' "$DURATION_FILE" >> "$REPORT"
    rm -f "$DURATION_FILE"
    grep -q 'ALERTA-DURACION:' "$REPORT" && alert=1 || true
  fi
else
  # Formatos ligero112: aceptar manifiestos OSU, FT y verificación funcional.
  case "$header" in
    job,grupo,ronda,celda,par,ranks,exit_code,verificacion*)
      while IFS=, read -r job grupo ronda celda par ranks ec verif transporte runlog; do
        [ "$job" = job ] && continue; [ -n "${job:-}" ] || continue
        : "$grupo" "$celda"
        case "$verif" in SALTADA*|SALTAADA*) skipped=$((skipped+1)); continue ;; esac
        cells=$((cells+1)); status=OK
        [ "$ec" = 0 ] && [ "$verif" = OK ] || status=REVISAR
        [ "$verif" = FALLO-PIN ] && { printf 'FALLO-PIN: %s (%s)\n' "$par" "$runlog" >> "$REPORT"; status=REVISAR; }
        if [ "$status" = OK ]; then valid=$((valid+1)); printf 'OK|%s\n' "$runlog" >> "$STATUS_FILE"; else issues=$((issues+1)); printf 'REVISAR|%s\n' "$runlog" >> "$STATUS_FILE"; fi
      done < "$MANIFEST" ;;
    job,ronda,par,ranks,exit_code,verificacion*)
      while IFS=, read -r job ronda par ranks ec verif transporte runlog; do
        [ "$job" = job ] && continue; [ -n "${job:-}" ] || continue
        case "$verif" in SALTADA*|SALTAADA*) skipped=$((skipped+1)); continue ;; esac
        cells=$((cells+1)); status=OK
        [ "$ec" = 0 ] && [ "$verif" = SUCCESSFUL ] || status=REVISAR
        [ "$verif" = FALLO-PIN ] && { printf 'FALLO-PIN: %s (%s)\n' "$par" "$runlog" >> "$REPORT"; status=REVISAR; }
        if [ "$status" = OK ]; then valid=$((valid+1)); printf 'OK|%s\n' "$runlog" >> "$STATUS_FILE"; else issues=$((issues+1)); printf 'REVISAR|%s\n' "$runlog" >> "$STATUS_FILE"; fi
      done < "$MANIFEST" ;;
    *)
      while IFS=, read -r pila transporte probe_exit observado coincide verif; do
        [ "$pila" = pila ] && continue; [ -n "${pila:-}" ] || continue
        case "$verif" in SALTADA*|SALTAADA*) skipped=$((skipped+1)); continue ;; esac
        cells=$((cells+1)); : "$observado" "$coincide"
        if [ "${verif:-}" = OK ] && [ "${probe_exit:-1}" = 0 ]; then valid=$((valid+1)); printf 'OK|%s\n' "$MANIFEST" >> "$STATUS_FILE"; else issues=$((issues+1)); printf 'REVISAR|%s\n' "$MANIFEST" >> "$STATUS_FILE"; fi
        [ "${verif:-}" = FALLO-PIN ] && printf 'FALLO-PIN: %s/%s\n' "$pila" "$transporte" >> "$REPORT"
      done < "$MANIFEST" ;;
  esac
fi

printf 'CELDAS VALIDAS: %d\n' "$valid" >> "$REPORT"
printf 'RUTAS VALIDAS:\n' >> "$REPORT"
if [ -f "${STATUS_FILE:-}" ]; then
  awk -F'|' '$1=="OK" && $2!="-" {print "- " $2}' "$STATUS_FILE" >> "$REPORT"
  rm -f "$STATUS_FILE"
fi
printf 'CELDAS REVISAR: %d\n' "$issues" >> "$REPORT"
printf 'CELDAS TOTAL: %d\n' "$cells" >> "$REPORT"
printf 'CELDAS SALTADAS: %d\n' "$skipped" >> "$REPORT"
rc=1
if [ "$issues" -eq 0 ] && [ "$alert" -eq 0 ]; then
  echo 'VEREDICTO: OK' >> "$REPORT"
  rc=0
else
  echo 'VEREDICTO: REVISAR' >> "$REPORT"
fi
cat "$REPORT"
if [ "$OUTPUT" != - ]; then
  cp "$REPORT" "$OUTPUT" || exit 2
fi
exit "$rc"
