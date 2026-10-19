#!/usr/bin/env python3
"""Figura 4 del artículo: una conclusión que dependía de un nodo.

FT clase D a 8 nodos, diagrama de caja vertical por par (caja = IQR, línea = mediana,
bigotes = 1,5 IQR, puntos = cada repetición). En cada par, a la izquierda las
asignaciones con b9p07 (83314 r2-6 y 83405 r7-11, n = 10) y a la derecha la
asignación sin b9p07 (84621 r2-6, n = 5).

Normas de Springer: sin títulos dentro de la figura (el mensaje va en el pie), letra
sans serif de 8 pt, ancho 129 mm, líneas >= 0,3 pt.

Entrada: data/derived/figuras/fig4_ft8n_runs.csv (generado por
analysis/figuras/extrae_fig4.py). Salida: paper/figures/fig4-asignacion.pdf.
Uso: python3 analysis/figuras/fig4_asignacion.py <repo>
"""
import csv
import random
import statistics as st
import sys
from collections import defaultdict
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Patch  # noqa: E402

repo = Path(sys.argv[1]).resolve()
src = repo / "data/derived/figuras"
dst = repo / "paper/figures"
dst.mkdir(parents=True, exist_ok=True)

# Color por condición: con b9p07 en gris, sin b9p07 en azul.
CON, SIN = "#8a8984", "#2a78d6"
INK, INK2, GRID = "#0b0b0b", "#52514e", "#e4e3df"
PAIRS = ["intel/mlx", "gcc/dc", "gcc/rc", "gcc/ud"]

plt.rcParams.update({"font.size": 8, "font.family": "sans-serif",
                     "font.sans-serif": ["Helvetica", "Arial", "Liberation Sans", "DejaVu Sans"],
                     "axes.edgecolor": INK2, "axes.labelcolor": INK, "xtick.color": INK,
                     "ytick.color": INK2, "axes.linewidth": 0.6, "ytick.major.width": 0.6,
                     "pdf.fonttype": 42})

runs = defaultdict(list)
for r in csv.DictReader((src / "fig4_ft8n_runs.csv").open()):
    if r["valido"] != "True":
        continue
    if r["job"] in ("83314", "84621") and int(r["ronda"]) == 1:  # calentamiento
        continue
    runs[(r["conjunto"], r["par"])].append(float(r["tiempo_s"]))
med = {k: st.median(v) for k, v in runs.items()}

MM = 1 / 25.4
fig, ax = plt.subplots(figsize=(129 * MM, 72 * MM))
random.seed(1)
D, W = 0.2, 0.32
for i, par in enumerate(PAIRS):
    for conj, dx, col, face in (("con b9p07", -D, CON, "white"), ("sin b9p07", +D, SIN, SIN)):
        v = runs[(conj, par)]
        x = i + dx
        bp = ax.boxplot(v, positions=[x], widths=W, patch_artist=True, showfliers=False,
                        whis=1.5, manage_ticks=False)
        for b in bp["boxes"]:
            b.set(facecolor=face, edgecolor=col, linewidth=1.0)
            if face != "white":
                b.set_facecolor((*matplotlib.colors.to_rgb(col), 0.25))
        for k in ("whiskers", "caps"):
            for ln in bp[k]:
                ln.set(color=col, linewidth=0.9)
        for ln in bp["medians"]:
            ln.set(color=col, linewidth=1.8)
        ax.scatter([x + random.uniform(-0.07, 0.07) for _ in v], v, s=9, color=col,
                   zorder=3, linewidths=0, alpha=0.9)
        top = max(v)
        ax.text(x, top + 0.18, f"{med[(conj, par)]:.2f}", ha="center", va="bottom",
                color=INK2 if conj == "con b9p07" else col,
                fontweight="bold" if conj == "sin b9p07" else "normal")
ax.set_xticks(range(len(PAIRS)))
ax.set_xticklabels(PAIRS)
ax.get_xticklabels()[0].set_fontweight("bold")
ax.set_xlim(-0.55, len(PAIRS) - 0.45)
ax.set_ylim(13.5, 21)
ax.set_ylabel("FT class D, 8 nodes: time per run (s)")
ax.grid(axis="y", color=GRID, lw=0.5)
ax.set_axisbelow(True)
for s_ in ("top", "right"):
    ax.spines[s_].set_visible(False)
ax.tick_params(axis="x", length=0)
ax.legend(handles=[Patch(facecolor="white", edgecolor=CON, label="allocations with b9p07 (n = 10)"),
                   Patch(facecolor=(*matplotlib.colors.to_rgb(SIN), 0.25), edgecolor=SIN,
                         label="allocation without b9p07 (n = 5)")],
          frameon=False, loc="upper right", handlelength=1.6)

fig.savefig(dst / "fig4-asignacion.pdf", bbox_inches="tight",
            metadata={"CreationDate": None, "ModDate": None})  # PDF reproducible
fig.savefig(dst / "fig4-asignacion.png", dpi=200, bbox_inches="tight")
print("ok", dst / "fig4-asignacion.pdf")
