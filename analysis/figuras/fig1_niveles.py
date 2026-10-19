#!/usr/bin/env python3
"""Figura 1 del artículo: niveles de la metodología, qué decide cada uno y su coste.

Costes en nodo-hora realmente consumidos en cpu112c (Tabla de coste, sacct de todos
los jobs del estudio): inventario 0,05; equivalencia 0,32; transportes 53,6 +
cargas 58,4 = 112; comparación entre asignaciones: sin coste adicional si las medidas
del nivel 3 se reparten en varias asignaciones (aquí, 3,0 de una confirmación dedicada).
Normas de Springer: sin título dentro, sans serif 8 pt, ancho 129 mm.
Uso: python3 analysis/figuras/fig1_niveles.py <repo>
"""
import sys
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import FancyBboxPatch  # noqa: E402

repo = Path(sys.argv[1]).resolve()
dst = repo / "paper/figures"; dst.mkdir(parents=True, exist_ok=True)
INK, INK2, BOX, ACC = "#0b0b0b", "#52514e", "#eef3fb", "#2a78d6"
plt.rcParams.update({"font.size": 8, "font.family": "sans-serif",
                     "font.sans-serif": ["Helvetica", "Arial", "Liberation Sans", "DejaVu Sans"],
                     "pdf.fonttype": 42})
LEVELS = [  # nombre, pregunta, decisión, coste (nodo-h), etiqueta de coste
    ("1  Inventory", "Is the partition what the\nscheduler declares?",
     "discrepancies to work around\n(SMT, binding, network adapter)", 0.05, "0.05"),
    ("2  Screening test", "Which nodes behave alike?",
     "execution groups;\nnodes to avoid", 0.32, "0.32"),
    ("3  Transports and\n    workloads", "Which stack, transport\nand placement?",
     "best configuration\nper workload", 112.0, "112"),
    ("4  Comparison across\n    allocations", "Does the result hold\non other nodes?",
     "sensitivity of results\nto the allocation", 3.0, "3.0*"),
]
W, H = 129, 80  # mm
fig = plt.figure(figsize=(W / 25.4, H / 25.4))
ax = fig.add_axes([0, 0, 1, 1]); ax.set_xlim(0, W); ax.set_ylim(0, H); ax.axis("off")
X0, BW, BH = 1, 37, 11.5      # caja de nivel
XD = 42                      # columna de decisión
XB0, XB1 = 92, 122            # barra de coste (log 0.01 .. 1000)
import math
def xb(v): return XB0 + (XB1 - XB0) * (math.log10(v) + 2) / 5
ytop = H - 9
ax.text(XD, H - 3, "What it decides", color=INK2, va="center", fontweight="bold")
ax.text(XB0, H - 3, "Cost (node-h)", color=INK2, va="center", fontweight="bold")
step = 14.5
for i, (name, q, d, c, lab) in enumerate(LEVELS):
    yc = ytop - i * step - BH / 2
    ax.add_patch(FancyBboxPatch((X0, yc - BH / 2), BW, BH, boxstyle="round,pad=0,rounding_size=1.5",
                                fc=BOX, ec=ACC, lw=0.8))
    ax.text(X0 + 2, yc, name, va="center", color=INK, fontweight="bold")
    ax.text(XD, yc, d, va="center", color=INK)
    ax.plot([XB0, XB1], [yc, yc], color="#e4e3df", lw=0.5, zorder=1)
    ax.plot([xb(c)], [yc], "o", ms=5, color=ACC if i < 3 else "white", mec=ACC, mew=1.0, zorder=3)
    ax.text(xb(c) + (-1.5 if i == 2 else 1.5), yc + 2.6, lab, va="center",
            ha="right" if i == 2 else "left", color=INK)
    if i < len(LEVELS) - 1:
        ax.annotate("", xy=(X0 + BW / 2, yc - BH / 2 - 3.0 + 0.2), xytext=(X0 + BW / 2, yc - BH / 2),
                    arrowprops=dict(arrowstyle="-|>", color=INK2, lw=0.8, mutation_scale=7))
# eje de la barra
ya = ytop - (len(LEVELS) - 1) * step - BH / 2 - 8
ax.plot([XB0, XB1], [ya, ya], color=INK2, lw=0.6)
for v, t in ((0.01, "0.01"), (1, "1"), (100, "100")):
    ax.plot([xb(v)] * 2, [ya, ya - 1.2], color=INK2, lw=0.6)
    ax.text(xb(v), ya - 2.2, t, ha="center", va="top", color=INK2)
# salida
yo = ya - 9
ax.add_patch(FancyBboxPatch((X0, yo - 4), BW, 7, boxstyle="round,pad=0,rounding_size=1.5",
                            fc=ACC, ec=ACC, lw=0.8))
ax.text(X0 + BW / 2, yo - 0.5, "Execution sheet", ha="center", va="center", color="white",
        fontweight="bold")
yc4 = ytop - 3 * step - BH / 2
ax.annotate("", xy=(X0 + BW / 2, yo + 3 + 0.2), xytext=(X0 + BW / 2, yc4 - BH / 2),
            arrowprops=dict(arrowstyle="-|>", color=INK2, lw=0.8, mutation_scale=7))
ax.text(XD, yo - 0.5, "groups and excluded nodes, stack, transport,\nplacement, warnings, date",
        va="center", color=INK2)
fig.savefig(dst / "fig1-niveles.pdf", metadata={"CreationDate": None, "ModDate": None})
fig.savefig(dst / "fig1-niveles.png", dpi=200)
print("ok")
