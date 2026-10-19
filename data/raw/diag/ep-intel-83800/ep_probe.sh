#!/usr/bin/env bash
# $1 = binario EP — lo lanza el rank (env heredado del rank: binding incluido)
"$1" & PID=$!
sleep 0.05
TH="$(grep Threads /proc/$PID/status 2>/dev/null | awk "{print \$2}")"
AF="$(taskset -pc $PID 2>/dev/null | awk "{print \$NF}")"
T1=$(awk "{print \$14}" /proc/$PID/stat 2>/dev/null)   # última muestra viva
wait $PID; RC=$?
CHU=$(times | tail -n1 | awk "{print \$1}")             # utime de hijos al wait
echo "rank=${OMPI_COMM_WORLD_RANK:-?} pid=$PID exit=$RC threads=${TH:-?} affinity=${AF:-?} utime_ticks=${T1:-NA} utime_children=$CHU"
exit $RC
