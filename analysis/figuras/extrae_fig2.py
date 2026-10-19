#!/usr/bin/env python3
"""Figura 2: datos por nodo de la prueba de equivalencia (cpu112c y cpu36c).

Ejecuta las dos primeras celdas de código de analysis/analisis.ipynb (lectura de
data/raw/equivalence y subparticiones de configuración), sin escribir sus salidas
(CC_EQ_OUT apunta a un directorio temporal), y guarda por nodo: partición,
subpartición, si pertenece a la referencia M, mediana de Triad y mediana de ancho de
banda a 4 MiB del par en que se midió (para pares con nodo de referencia fijo, el otro
nodo; para pares disjuntos, ambos).
Salida: data/derived/figuras/fig2_nodos.csv. Uso: python3 analysis/figuras/extrae_fig2.py <repo>
"""
import csv, json, os, statistics, sys, tempfile
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
os.environ["CC_REPO"] = str(repo)
os.environ["CC_EQ_OUT"] = tempfile.mkdtemp()
nb = json.loads((repo / "analysis/analisis.ipynb").read_text())
code = ["".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "code"]
ns = {}
exec(code[0], ns); exec(code[1], ns)
med = statistics.median
REF = {"cpu112c": "b9p01", "cpu36c": ("aac102", "acc101")}
rows = []
for part in ("cpu112c", "cpu36c"):
    sub = {n: g["id"] for g in ns["config"][part] for n in g["nodes"]}
    M = ns["M_NODES"][part]
    refs = REF[part] if isinstance(REF[part], tuple) else (REF[part],)
    bwn = {}
    for p, v in ns["bw"].items():
        a, b = p.split("|")
        if a not in sub:
            continue
        others = [x for x in (a, b) if x not in refs] or [a, b]
        for x in others:
            bwn.setdefault(x, med(v))
    for n in sorted(sub):
        rows.append({"particion": part, "nodo": n, "subparticion": sub[n], "referencia": n in M,
                     "triad_MBs": round(med(ns["triad"][n]), 1) if n in ns["triad"] else "",
                     "bw_4MiB_MBs": round(bwn[n], 1) if n in bwn else ""})
out = repo / "data/derived/figuras"; out.mkdir(parents=True, exist_ok=True)
with (out / "fig2_nodos.csv").open("w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
print(len(rows), "nodos")
