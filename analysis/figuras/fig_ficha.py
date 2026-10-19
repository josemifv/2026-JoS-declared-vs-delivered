#!/usr/bin/env python3
"""Figura: seguir la ficha de ejecución frente a un lanzamiento ingenuo (cpu36c, FT clase D, 8 nodos).

Ocho asignaciones alternas en orden temporal (N = ingenua, R = recomendada), rondas 2-6.
Punto: ejecución terminada (tiempo de FT); aspa en la banda superior: ronda colgada (detenida
por el límite de tiempo). Debajo de cada asignación, si mezcla nodos con y sin SMT.
Entrada: data/derived/figuras/fig_ficha.csv (analysis/figuras/extrae_fig_ficha.py).
Salida: paper/figures/fig-ficha.pdf
Uso: python3 analysis/figuras/fig_ficha.py <repo>
"""
import csv, statistics as st, sys
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

repo = Path(sys.argv[1]).resolve()
dst = repo / "paper/figures"; dst.mkdir(parents=True, exist_ok=True)
ACC, WARN, INK, INK2, GRID = "#2a78d6", "#c2410c", "#0b0b0b", "#52514e", "#e4e3df"
plt.rcParams.update({"font.size": 8, "font.family": "sans-serif",
                     "font.sans-serif": ["Helvetica", "Arial", "Liberation Sans", "DejaVu Sans"],
                     "axes.edgecolor": INK2, "axes.linewidth": 0.6, "xtick.color": INK,
                     "ytick.color": INK2, "pdf.fonttype": 42})
R = [r for r in csv.DictReader((repo / "data/derived/figuras/fig_ficha.csv").open())
     if r["mode"] in ("naive", "recommended")]
allocs = list(dict.fromkeys(r["alloc"] for r in R))
HUNG_Y = 33.4
fig, ax = plt.subplots(figsize=(129 / 25.4, 55 / 25.4))
for x, a in enumerate(allocs):
    rs = [r for r in R if r["alloc"] == a]
    c = ACC if rs[0]["mode"] == "recommended" else WARN
    done = [float(r["time_s"]) for r in rs if r["status"] == "completed"]
    hung = sum(r["status"] == "hung" for r in rs)
    offs = [(-0.24 + 0.12 * i) for i in range(5)]
    ax.scatter([x + o for o in offs[:len(done)]], done, s=10, color=c, zorder=3, lw=0)
    if hung:
        ax.scatter([x + o for o in offs[:hung]], [HUNG_Y] * hung, marker="x", s=14, color=c, lw=1, zorder=3)
for m, c, lab in (("naive", WARN, "naive"), ("recommended", ACC, "execution sheet")):
    v = [float(r["time_s"]) for r in R if r["mode"] == m and r["status"] == "completed"]
    n = sum(r["mode"] == m for r in R)
    ax.axhline(st.median(v), color=c, lw=0.8, ls=(0, (3, 2)), zorder=1)
    ax.text(len(allocs) - 0.45, st.median(v), f"{lab}: median {st.median(v):.2f} s,\n{len(v)} of {n} completed",
            fontsize=6.5, color=c, va="center", ha="left")
ax.axhspan(32.9, 33.9, color=GRID, zorder=0)
ax.text(-0.5, HUNG_Y, "hung", fontsize=6.5, color=INK2, va="center", ha="left")
mix = {r["alloc"]: r["mixed_smt"] for r in R}
ax.set_xticks(range(len(allocs)))
ax.set_xticklabels([f"{a}\n{'mixed' if mix[a] == '1' else 'SMT off'}" for a in allocs])
ax.set_xlim(-0.6, len(allocs) + 1.6); ax.set_ylim(28.0, 34.0)
ax.set_yticks([28, 29, 30, 31, 32]); ax.set_ylabel("FT class D, 8 nodes (s)")
ax.grid(axis="y", color=GRID, lw=0.5); ax.set_axisbelow(True)
for s in ("top", "right"):
    ax.spines[s].set_visible(False)
ax.set_xlabel("Allocation, in order of execution (N, naive; R, following the sheet) and SMT state of its nodes")
fig.savefig(dst / "fig-ficha.pdf", bbox_inches="tight")
fig.savefig(dst / "fig-ficha.png", bbox_inches="tight", dpi=200)
print("ok")
