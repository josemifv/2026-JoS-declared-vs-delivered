#!/usr/bin/env python3
"""Nodos de cada asignación de la fase B (matriz y L9a/L9b de intelc) y mediana por celda y par.
Persona, 2026-10-09 (orden informes/ordenes/2026-10-09-T26-b9p07.md); informe:
informes/2026-10-09-analisis-intelc.md. Los nodos salen de los run.log (líneas de pinning de
Intel MPI y de UCX): en asignaciones de varios tamaños (83314-83318, 83405-83407) son los de la
asignación completa. Columna «b9p07»: si la asignación incluye b9p07.
Rondas: «efectivas» (2-11) y, solo en los jobs de intelc (humo L9a y L9b), «r1» (calentamiento),
porque el humo L9a solo tiene esa ronda; las r1 se comparan solo entre sí.
Uso: python3 analysis/nodos_faseb.py .            (todas las celdas de FT, CG y MG)
     python3 analysis/nodos_faseb.py . 8n         (solo las celdas de 8 nodos)"""
import re, sys, statistics as st
from collections import defaultdict
from pathlib import Path
REPO = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(REPO / "analysis"))
import fase_b_loader as B  # noqa: E402
TALLA = sys.argv[2] if len(sys.argv) > 2 else ""
NOD = re.compile(r" (b\d+p\d+) ")
runs = defaultdict(list)
for jd in sorted((B.RAW / "phaseB").glob("faseB-*")):
    if not jd.is_dir():
        continue
    n, _, _ = B.carga_job(jd)
    for r in n:
        if (r.get("time_s") and (r["status"] == "efectiva" or (r["tipo"] == "intelc" and r["ronda"] == "1"))
                and not r.get("reetiquetada")
                and r["tipo"] in ("matriz", "intelc") and r["celda"].split("-")[0] in ("ft", "cg", "mg")
                and r["celda"].endswith(TALLA)):
            clase = "r1" if r["ronda"] == "1" else "efectivas"
            runs[(r["celda"], r["par"], r["job"], jd.name, clase)].append(r["time_s"])
def nodos(jdname, celda):
    """Nodos de la asignación: del run.log de cualquier par de la misma celda que los imprima
    (Intel MPI los imprime; OpenMPI/UCX no). Todas las celdas de un job comparten asignación."""
    s = set()
    for rl in sorted((B.RAW / "phaseB" / jdname).glob(f"{celda}-*/run.log")):
        s |= set(NOD.findall(rl.read_text(errors="replace")))
        if s:
            break
    return sorted(s, key=lambda x: int(x.split("p")[1]))
print("celda | par | job | rondas | n | mediana (s) | b9p07 | nodos")
for (celda, par, job, jdn, clase), v in sorted(runs.items()):
    s = nodos(jdn, celda)
    print(f"{celda} | {par} | {job} | {clase} | {len(v)} | {st.median(v):.2f} | {'sí' if 'b9p07' in s else ('no' if s else '?')} | {' '.join(s) or '?'}")
