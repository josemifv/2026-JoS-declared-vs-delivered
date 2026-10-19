#!/usr/bin/env python3
"""Figura 4: datos por run de FT-8n (con y sin b9p07) y ancho de banda de los pares de equivalencia.

Reutiliza los helpers de analysis/b9p07.py (manifiesto + cmdlog por hash). Solo lee data/raw.
Salida: data/derived/figuras/fig4_ft8n_runs.csv y fig4_bw_pares.csv.
Uso: python3 analysis/figuras/extrae_fig4.py <repo>
"""
import csv, json, re, statistics, sys
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(repo / "analysis"))
import b9p07 as h  # noqa: E402

raw = repo / "data/raw"
out = repo / "data/derived/figuras"
out.mkdir(parents=True, exist_ok=True)

JOBS = {  # job -> (directorio, conjunto de asignación)
    "83314": ("phaseB/faseB-stream_ep_ft-83314", "con b9p07"),
    "83405": ("phaseB/faseB-ep_ft-83405", "con b9p07"),
    "84621": ("b9p07/B/faseB-ep_ft-84621", "sin b9p07"),
}
rows = []
for job, (rel, conjunto) in JOBS.items():
    d = raw / rel
    index = h.manifest_index(d)
    entries = [json.loads(l) for l in (d / "commands.jsonl").read_text().splitlines() if l.strip()]
    for j in sorted(entries, key=lambda x: x.get("ts", "")):
        cmd = j.get("cmd", [])
        npb = h.NPB.search(" ".join(cmd))
        if not npb:
            continue
        kernel, pila, nr = npb.group(3), npb.group(1), h.ranks(cmd)
        q = index.get((kernel, pila, nr))
        f = q.popleft() if q else None
        if kernel != "ft" or nr != 512 or f is None:
            continue
        text = h.read(h.output_path(j, d, raw))
        m = h.TIME.search(text)
        ok = (j.get("exit_code") == 0 and f.get("verificacion") == "SUCCESSFUL"
              and bool(re.search(r"Verification\s*=\s*SUCCESSFUL\b", text)))
        rows.append({"job": job, "conjunto": conjunto, "par": f["par"], "ronda": int(f["ronda"]),
                     "tiempo_s": float(m.group(1)) if m else "", "valido": ok})
with (out / "fig4_ft8n_runs.csv").open("w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0]))
    w.writeheader(); w.writerows(rows)

# Ancho de banda a 4 MiB de los pares de cpu112c (prueba de equivalencia)
sacct = {}
for l in (repo / "informes/coste/sacct-turgalium-2026-10-11.txt").read_text().splitlines():
    f = l.split("|")
    if len(f) > 11 and f[0].isdigit():
        sacct[f[0]] = f
pares = []
for d in sorted((raw / "equivalence/turgalium").iterdir()):
    f = sacct.get(d.name)
    if not f or f[2] != "cpu112c" or f[3] != "2" or not (d / "commands.jsonl").is_file():
        continue
    vals = []
    for l in (d / "commands.jsonl").read_text().splitlines():
        try:
            j = json.loads(l)
        except ValueError:
            continue
        if "osu_bw" not in " ".join(j.get("cmd", [])):
            continue
        for ln in h.read(h.output_path(j, d, raw)).splitlines():
            m = re.match(r"\s*4194304\s+([\d.]+)", ln)
            if m:
                vals.append(float(m.group(1)))
    if vals:
        pares.append({"job": d.name, "nodos": f[11], "n": len(vals),
                      "bw_4MiB_MBs_mediana": round(statistics.median(vals), 1)})
with (out / "fig4_bw_pares.csv").open("w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(pares[0]))
    w.writeheader(); w.writerows(pares)
print(len(rows), "runs FT-8n;", len(pares), "pares")
