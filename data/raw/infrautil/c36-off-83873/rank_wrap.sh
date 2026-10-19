#!/usr/bin/env bash
# $1 = fichero cpu-por-rank; resto = comando a ejecutar en el rank
R="${OMPI_COMM_WORLD_RANK:-0}"
CPU="$(sed -n "$(( RANK + 1 ))p" "$1")"
shift
exec taskset -c "$CPU" "$@"
