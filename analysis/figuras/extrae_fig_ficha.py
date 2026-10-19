#!/usr/bin/env python3
"""Extrae los datos de la figura «ficha frente a lanzamiento ingenuo» (L14c, T19, cpu36c).

Para cada una de las ocho asignaciones (cuatro ingenuas y cuatro recomendadas, alternas) y
cada ronda efectiva (2-6; la 1 es de calentamiento), registra si FT clase D a 8 nodos
terminó y su tiempo. Una ronda cuyo mapcheck se colgó no llega a lanzar FT y cuenta como
colgada. Las celdas de control (gcc por defecto dentro de las asignaciones recomendadas) se
registran aparte.
Entrada: data/raw/infrautil/ed36-{ingenuo,recomendado}-864{26..33}/{manifest.csv,nodos-smt.txt,rN/run.log}
Salida: data/derived/figuras/fig_ficha.csv
Uso: python3 analysis/figuras/extrae_fig_ficha.py <repo> [salida.csv]
"""
import csv, re, sys
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
raw = repo / "data/raw/infrautil"
out = Path(sys.argv[2]) if len(sys.argv) > 2 else repo / "data/derived/figuras/fig_ficha.csv"
out.parent.mkdir(parents=True, exist_ok=True)
JOBS = [(86426, "naive"), (86427, "recommended"), (86428, "naive"), (86429, "recommended"),
        (86430, "naive"), (86431, "recommended"), (86432, "naive"), (86433, "recommended")]
rows = []
for k, (job, mode) in enumerate(JOBS):
    d = raw / f"ed36-{'ingenuo' if mode == 'naive' else 'recomendado'}-{job}"
    smt = [l.split()[1] for l in (d / "nodos-smt.txt").read_text().split("\n") if l.strip()]
    mixed = "SMT=2" in smt and "SMT=1" in smt
    man = list(csv.DictReader((d / "manifest.csv").open()))
    label = f"{'N' if mode == 'naive' else 'R'}{k // 2 + 1}"
    for r in range(2, 7):
        cells = {m["celda"]: m for m in man if m["ronda"] == str(r)}
        ft = cells.get("ft-8n")
        if ft and ft["verificacion"] == "SUCCESSFUL":
            txt = (d / f"r{r}" / "run.log").read_text(errors="replace")
            t = float(re.search(r"Time in seconds =\s+([0-9.]+)", txt).group(1))
            status = "completed"
        else:
            t, status = "", "hung"
        rows.append(dict(job=job, mode=mode, alloc=label, mixed_smt=int(mixed), round=r,
                         status=status, time_s=t))
    for m in man:
        if m["celda"].startswith("control"):
            rows.append(dict(job=job, mode="control", alloc=label, mixed_smt=int(mixed),
                             round=m["celda"], status="completed" if m["exit_code"] == "0" else "hung",
                             time_s=""))
with out.open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
print(out, len(rows))
