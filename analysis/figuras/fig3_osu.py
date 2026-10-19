#!/usr/bin/env python3
"""Figura 3 del artículo: perfil OSU de los 7 pares en cpu112c (fase A).

Ralentización respecto al mejor par en cada métrica (latencia 8 B, ancho de banda
4 MiB, allreduce y alltoall 64 KiB a 512 ranks): mediana (punto) e IQR (segmento), n = 10.
Puntos individuales del allreduce bimodal de intel/mlx. Color = pares seleccionados
por R2; columna final = puntuación R2 (posición media en las 4 métricas).
Entrada: data/derived/phaseA/{celdas.csv,runs.csv,r2.json}. Salida: paper/figures/fig3-osu.pdf.
Uso: python3 analysis/figuras/fig3_osu.py <repo>
"""
import csv, json, sys
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

repo = Path(sys.argv[1]).resolve()
src = repo / "data/derived/phaseA"
dst = repo / "paper/figures"; dst.mkdir(parents=True, exist_ok=True)
ACC, OTH, INK, INK2, GRID = "#2a78d6", "#8a8984", "#0b0b0b", "#52514e", "#e4e3df"
plt.rcParams.update({"font.size": 8, "font.family": "sans-serif",
                     "font.sans-serif": ["Helvetica", "Arial", "Liberation Sans", "DejaVu Sans"],
                     "axes.edgecolor": INK2, "axes.linewidth": 0.6, "xtick.color": INK2,
                     "ytick.color": INK, "xtick.major.width": 0.6, "pdf.fonttype": 42})
METRICS = [("latency", "8", False, "Latency\n8 B"), ("bw", "4194304", True, "Bandwidth\n4 MiB"),
           ("allreduce", "65536", False, "Allreduce\n64 KiB"), ("alltoall", "65536", False, "All-to-all\n64 KiB")]
cel = {(r["par"], r["prueba"]): r for r in csv.DictReader((src / "celdas.csv").open())}
r2 = json.load((src / "r2.json").open())["oficial"]
score, sel = r2["puntuacion"], set(r2["seleccion"])
pairs = sorted(score, key=lambda p: score[p])           # mejor arriba
runs = [r for r in csv.DictReader((src / "runs.csv").open()) if r["status"] == "efectiva"]

fig, axes = plt.subplots(1, 5, figsize=(129 / 25.4, 62 / 25.4), sharey=True,
                         gridspec_kw={"width_ratios": [1, 1, 1, 1, 0.45], "wspace": 0.12})
Y = {p: len(pairs) - 1 - i for i, p in enumerate(pairs)}
for ax, (t, m, hb, title) in zip(axes, METRICS):
    vals = {p: float(cel[(p, t)]["mediana"]) for p in pairs if (p, t) in cel}
    best = max(vals.values()) if hb else min(vals.values())
    f = (lambda v: best / v) if hb else (lambda v: v / best)
    for p in pairs:
        c = ACC if p in sel else OTH
        if (p, t) not in cel:
            ax.text(1.05, Y[p], "n/a", va="center", color=INK2, fontsize=7)
            continue
        r = cel[(p, t)]
        lo, hi = sorted((f(float(r["q1"])), f(float(r["q3"]))))
        ax.plot([lo, hi], [Y[p]] * 2, color=c, lw=1.6, solid_capstyle="butt", zorder=2)
        if p == "intel/mlx" and t == "allreduce":
            xs = [f(float(x["value"])) for x in runs if x["pair"] == p and x["test"] == t]
            ax.scatter(xs, [Y[p]] * len(xs), s=7, facecolor="white", edgecolor=c, lw=0.7, zorder=3)
        ax.plot([f(vals[p])], [Y[p]], "o", ms=3.6, color=c, zorder=4)
    ax.set_xscale("log")
    ax.set_xlim(0.8, 60)
    ax.set_xticks([1, 3, 10, 30]); ax.set_xticklabels(["1", "3", "10", "30"])
    ax.minorticks_off()
    ax.grid(axis="x", color=GRID, lw=0.5); ax.set_axisbelow(True)
    ax.set_title(title, fontsize=8, color=INK, pad=4)
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.tick_params(axis="y", length=0)
axes[0].set_yticks([Y[p] for p in pairs]); axes[0].set_yticklabels(pairs)
for lab in axes[0].get_yticklabels():
    if lab.get_text() in sel:
        lab.set_color(ACC); lab.set_fontweight("bold")
fig.text(0.47, -0.02, "slowdown with respect to the best configuration (log scale)", ha="center", color=INK)
sx = axes[4]
for p in pairs:
    sx.text(0.5, Y[p], f"{score[p]:.2f}", ha="center", va="center",
            color=ACC if p in sel else INK2, fontweight="bold" if p in sel else "normal")
sx.set_title("R2\nscore", fontsize=8, color=INK, pad=4)
sx.set_xlim(0, 1); sx.set_xticks([]); sx.tick_params(left=False); sx.set_ylim(-0.6, len(pairs) - 0.4)
for s in ("top", "right", "left", "bottom"):
    sx.spines[s].set_visible(False)
fig.savefig(dst / "fig3-osu.pdf", bbox_inches="tight", metadata={"CreationDate": None, "ModDate": None})
fig.savefig(dst / "fig3-osu.png", dpi=200, bbox_inches="tight")
print("ok")
