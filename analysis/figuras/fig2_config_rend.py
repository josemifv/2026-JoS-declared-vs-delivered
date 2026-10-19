#!/usr/bin/env python3
"""Figura 2 del artículo: la configuración no predice el rendimiento.

Por nodo de cpu36c y cpu112c: desviación de STREAM Triad (x) y del ancho de banda a
4 MiB de su par (y) respecto a la mediana de los nodos con la configuración mayoritaria
de su clase. Círculo relleno = configuración mayoritaria (cpu36c: subparticiones 0 y 1,
SMT off/on; cpu112c: subpartición 2); cuadrado hueco = configuración distinta. Banda gris:
±5 % (R1). Los nodos de referencia de los pares (b9p01, aac102, acc101) no tienen ancho de
banda propio y se omiten del eje y (se dibujan en y = 0 con marca de referencia).
Entrada: data/derived/figuras/fig2_nodos.csv. Salida: paper/figures/fig2-config.pdf.
Uso: python3 analysis/figuras/fig2_config_rend.py <repo>
"""
import csv, statistics as st, sys
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

repo = Path(sys.argv[1]).resolve()
rows = list(csv.DictReader((repo / "data/derived/figuras/fig2_nodos.csv").open()))
dst = repo / "paper/figures"; dst.mkdir(parents=True, exist_ok=True)
ACC, OTH, INK, INK2, GRID, BAND = "#2a78d6", "#8a8984", "#0b0b0b", "#52514e", "#e4e3df", "#efeeea"
plt.rcParams.update({"font.size": 8, "font.family": "sans-serif",
                     "font.sans-serif": ["Helvetica", "Arial", "Liberation Sans", "DejaVu Sans"],
                     "axes.edgecolor": INK2, "axes.linewidth": 0.6, "xtick.color": INK2,
                     "ytick.color": INK2, "pdf.fonttype": 42})
MAJ = {"cpu36c": {"0", "1"}, "cpu112c": {"2"}}
fig, axes = plt.subplots(1, 2, figsize=(129 / 25.4, 60 / 25.4), sharey=True,
                         gridspec_kw={"wspace": 0.12})
for ax, part in zip(axes, ("cpu36c", "cpu112c")):
    rs = [r for r in rows if r["particion"] == part]
    maj = [r for r in rs if r["subparticion"] in MAJ[part]]
    tref = st.median(float(r["triad_MBs"]) for r in maj)
    bref = st.median(float(r["bw_4MiB_MBs"]) for r in maj if r["bw_4MiB_MBs"])
    from matplotlib.patches import Rectangle
    ax.add_patch(Rectangle((-5, -5), 10, 10, color=BAND, zorder=0, lw=0))
    inside = dis_in = 0
    for r in rs:
        x = 100 * (float(r["triad_MBs"]) / tref - 1)
        y = 100 * (float(r["bw_4MiB_MBs"]) / bref - 1) if r["bw_4MiB_MBs"] else 0.0
        m = r["subparticion"] in MAJ[part]
        out = abs(x) > 5 or abs(y) > 5
        if not out:
            inside += 1; dis_in += (not m)
        c = ACC if out else OTH
        if m:
            ax.plot(x, y, "o", ms=4.2, color=c, mec="white", mew=0.4, zorder=3)
        else:
            ax.plot(x, y, "s", ms=4.2, mfc="white", mec=c, mew=1.0, zorder=3)
        if out:
            dx, ha = (1.5, "left") if x > -10 else (-1.5, "right")
            if r["nodo"] == "acc111":
                ax.text(x + 1.5, y - 3.5, r["nodo"], ha="left", va="center", color=ACC, fontweight="bold")
            elif r["nodo"] == "aac111":
                ax.text(x + 1.5, y + 3.5, r["nodo"], ha="left", va="center", color=ACC, fontweight="bold")
            else:
                ax.text(x + dx, y, r["nodo"], ha=ha, va="center", color=ACC, fontweight="bold")
    nmaj, ndis = len(maj), len(rs) - len(maj)
    ax.set_title(f"{part}: {nmaj} nodes with the majority configuration,\n{ndis} with a distinct one",
                 fontsize=8, color=INK, loc="left") if False else None
    ax.annotate(f"{inside} nodes within 5 %,\n{dis_in} of them with a\ndistinct configuration",
                xy=(-1, -4), xytext=(-12, -14), color=INK2, ha="center", va="center",
                arrowprops=dict(arrowstyle="-", color=INK2, lw=0.6))
    ax.text(0.02, 0.98, part, transform=ax.transAxes, fontweight="bold", va="top", color=INK)
    ax.set_xlim(-22, 8); ax.set_ylim(-45, 8)
    ax.set_xticks([-20, -10, 0]); ax.set_yticks([-40, -30, -20, -10, 0])
    ax.set_xlabel("STREAM Triad vs majority (%)")
    ax.grid(color=GRID, lw=0.5); ax.set_axisbelow(True)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
axes[0].set_ylabel("pair bandwidth, 4 MiB,\nvs majority (%)")
from matplotlib.lines import Line2D  # noqa: E402
axes[0].legend(handles=[Line2D([], [], ls="", marker="o", ms=4.2, color=OTH, label="majority configuration"),
                        Line2D([], [], ls="", marker="s", ms=4.2, mfc="white", mec=OTH, mew=1.0,
                               label="distinct configuration")],
               frameon=False, loc="lower left")
fig.savefig(dst / "fig2-config.pdf", bbox_inches="tight", metadata={"CreationDate": None, "ModDate": None})
fig.savefig(dst / "fig2-config.png", dpi=200, bbox_inches="tight")
print("ok")
