#!/usr/bin/env bash
# $1 = binario EP — lo lanza el rank (env heredado del rank: binding incluido)
"$1" & PID=$!
T0=$(awk "{print \$14}" /proc/$PID/stat 2>/dev/null || echo 0)
sleep 0.05
TH="$(grep Threads /proc/$PID/status 2>/dev/null | awk "{print \$2}")"
AF="$(taskset -pc $PID 2>/dev/null | awk "{print \$NF}")"
wait $PID
T1=$(awk "{print \$14}" /proc/$PID/stat 2>/dev/null || echo "?")
echo "rank=${OMPI_COMM_WORLD_RANK:-?} pid=$PID threads=${TH:-?} affinity=${AF:-?} utime_ticks=$(( ${T1:-0} - ${T0:-0} ))"
