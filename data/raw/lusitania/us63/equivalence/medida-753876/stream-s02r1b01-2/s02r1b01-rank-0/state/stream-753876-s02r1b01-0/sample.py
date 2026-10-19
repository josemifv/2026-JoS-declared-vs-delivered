import json, os, sys, time, glob

out, interval = sys.argv[1], float(sys.argv[2])
stopfile = out + ".stop"

def freq():
    vals = []
    for p in sorted(glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq")):
        try:
            with open(p) as f:
                vals.append(int(f.read().strip()))
        except (OSError, ValueError):
            return None
    return vals or None

def energy():
    for p in sorted(glob.glob("/sys/class/powercap/intel-rapl:*/energy_uj")):
        try:
            with open(p) as f:
                return int(f.read().strip())
        except (OSError, ValueError):
            return None
    return None

with open(out, "a") as fh:
    while not os.path.exists(stopfile):
        rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
               "freq_khz": freq(), "energy_uj": energy()}
        fh.write(json.dumps(rec) + "\n")
        fh.flush()
        time.sleep(interval)
