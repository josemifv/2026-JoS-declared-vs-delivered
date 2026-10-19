#!/usr/bin/env python3
"""Figure: FT class D at 8 nodes on cpu112c, median per configuration in every
8-node allocation of the study with effective runs, in date order. Replaces
Table 4 and Fig. 4 of v10h in the short version (both kept in Online Resource 1).

Values are the medians of Table 4 of v10h (data/derived/figuras/fig4_ft8n_runs.csv;
data/raw/phaseB/faseB-ep_ft-84513; data/raw/ligero112/ft8n112-{84920,85916}/*/run.log),
verified by the v10h referee against the repository; intel/verbs 14.30 / 14.51 s from
ft8n112-{84920,85916}/ft-intel-verbs;ofi_rxm-r1/run.log (review v10h, check 2).
n = effective runs per configuration. Shaded band: allocations that included b9p07.
v10j (review v10i item A.8): markers offset horizontally where they would overlap
(84621, 84920, 85916) and dotted connectors drawn only between consecutive allocations
in which the configuration was measured (no line across 84513 for the gcc configurations).

Output: <out>/fig-ft8n-allocations.pdf (and .png)
Usage: python3 fig_ft8n_allocations.py <out dir (figures)>
"""
import sys
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402

dst = Path(sys.argv[1]).resolve(); dst.mkdir(parents=True, exist_ok=True)
INK, INK2, GRID, BAND = "#0b0b0b", "#52514e", "#e4e3df", "#efeeea"
plt.rcParams.update({"font.size": 8, "font.family": "sans-serif",
                     "font.sans-serif": ["Helvetica", "Arial", "Liberation Sans", "DejaVu Sans"],
                     "axes.edgecolor": INK2, "axes.linewidth": 0.6, "xtick.color": INK,
                     "ytick.color": INK, "pdf.fonttype": 42})

# job, date, b9p07, n, {configuration: median FT time (s)}   -- Table 4 of v10h
JOBS = [
    ("83314", "4 Oct", True, 5, {"intel/mlx": 19.78, "gcc/dc": 15.96, "gcc/rc": 16.73, "gcc/ud": 17.22}),
    ("83405", "4 Oct", True, 5, {"intel/mlx": 19.63, "gcc/dc": 15.95, "gcc/rc": 16.65, "gcc/ud": 17.08}),
    ("84513", "9 Oct", False, 10, {"intel/mlx": 14.16, "intelc/mlx": 12.07}),
    ("84621", "9 Oct", False, 5, {"intel/mlx": 14.22, "gcc/dc": 14.61, "gcc/rc": 15.63, "gcc/ud": 14.29}),
    ("84920", "13 Oct", False, 1, {"intel/mlx": 14.09, "gcc/dc": 14.44, "gcc/rc": 17.90,
                                   "intelc/mlx": 11.98, "intel/verbs": 14.30}),
    ("85916", "15 Oct", False, 1, {"intel/mlx": 14.12, "gcc/dc": 14.40, "gcc/rc": 17.75,
                                   "intelc/mlx": 11.94, "intel/verbs": 14.51}),
]
# configuration: colour, marker, horizontal offset (legibility only; values unchanged)
CFG = {"intel/mlx": ("#2a78d6", "o", -0.11), "gcc/dc": ("#2f8f5b", "D", 0.11), "gcc/rc": ("#c2410c", "s", 0.0),
       "gcc/ud": ("#7c4dbd", "^", 0.0), "intelc/mlx": ("#0b0b0b", "v", 0.0), "intel/verbs": ("#8a8984", "P", 0.0)}

fig, ax = plt.subplots(figsize=(129 / 25.4, 49 / 25.4))
xs = list(range(len(JOBS)))
# band over the allocations with b9p07
ax.axvspan(-0.5, 1.5, color=BAND, lw=0, zorder=0)
ax.text(0.5, 11.2, "allocations with b9p07", ha="center", va="bottom", fontsize=7, color=INK2)
ax.text(3.5, 11.2, "allocations without b9p07", ha="center", va="bottom", fontsize=7, color=INK2)
for cfg, (col, mk, dx) in CFG.items():
    pts = [(x + dx, j[4][cfg]) for x, j in zip(xs, JOBS) if cfg in j[4]]
    # connectors only between consecutive allocations that both measured the configuration
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if round(x1 - x0) == 1:
            ax.plot([x0, x1], [y0, y1], ls=(0, (1.5, 2)), lw=0.7, color=col, zorder=2)
    ax.plot([p[0] for p in pts], [p[1] for p in pts], ls="", marker=mk, ms=4.6 if mk != "D" else 3.8,
            color=col, mec="white", mew=0.4, zorder=3)
ax.set_xticks(xs)
ax.set_xticklabels([f"{j[0]}\n{j[1]}\n$n$ = {j[3]}" for j in JOBS], fontsize=7)
ax.set_xlim(-0.5, len(JOBS) - 0.5)
ax.set_ylim(11, 20.6); ax.set_yticks([12, 14, 16, 18, 20])
ax.set_ylabel("FT class D, 8 nodes (s)")
ax.set_xlabel("Allocation (Slurm job, date, effective runs per configuration), in order of execution")
ax.grid(axis="y", color=GRID, lw=0.5); ax.set_axisbelow(True)
for s in ("top", "right"):
    ax.spines[s].set_visible(False)
ax.legend(handles=[Line2D([], [], ls="", marker=mk, ms=4.6 if mk != "D" else 3.8, color=col, mec="white",
                          mew=0.4, label=cfg) for cfg, (col, mk, _) in CFG.items()],
          frameon=False, loc="upper right", bbox_to_anchor=(1.0, 1.0), fontsize=7, ncol=3,
          handletextpad=0.3, columnspacing=0.9, labelspacing=0.3)
fig.savefig(dst / "fig-ft8n-allocations.pdf", bbox_inches="tight", metadata={"CreationDate": None, "ModDate": None})
fig.savefig(dst / "fig-ft8n-allocations.png", bbox_inches="tight", dpi=200)
print("ok")
