#!/usr/bin/env python3
"""Figure: STREAM Triad per node with the scheduler's default thread placement
(A, as in the screening test) and with threads pinned to cores (B), on Xula,
Lusitania and Turgalium cpu36c (follow-up T53, 18-19 October 2026, one exclusive
1-node job per node, 22 rounds alternating A/B, the first of each discarded,
n = 10 per placement). v10l: Turgalium panel added (Part C); each of its four
nodes was measured in two jobs (the second launch was an accidental repetition),
both drawn on the same row as two markers.

Dot, median; segment, min-max of the 10 effective rounds. Open grey, default
placement; filled blue, pinned (OMP_PLACES=cores, OMP_PROC_BIND=spread,
OMP_NUM_THREADS = physical cores counted by lscpu). The two SMT nodes (xula5204,
s02r2b01) receive only the cores of one socket (the job's cpuset is NUMA node 0),
so the pinned placement put two threads per core there; they are drawn with a
square marker. v10j (review v10i item A.2): legend and axis titles reworded.

Inputs (manifests copied from the carril-c checkout, commit 1cd5c059; Turgalium
manifests copied 19 Oct 2026 from carril-c data/raw/turgalium/triad-binding):
  <data>/xula/triad-binding/<node>-<job>/manifest.csv
  <data>/lusitania/triad-binding/<node>-<job>/manifest.csv
  <data>/turgalium/triad-binding/<node>-<job>/manifest.csv (two jobs per node)
  columns: ronda,colocacion,warmup,threads,exit_code,verificacion,triad_MBps
Output: <out>/fig-t53-pinned.pdf (and .png)
Usage: python3 fig_t53_pinned.py <data dir (t53-data)> <out dir (figures)>
"""
import csv, glob, statistics as st, sys
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402

data = Path(sys.argv[1]).resolve()
dst = Path(sys.argv[2]).resolve(); dst.mkdir(parents=True, exist_ok=True)
ACC, OTH, INK, INK2, GRID = "#2a78d6", "#8a8984", "#0b0b0b", "#52514e", "#e4e3df"
plt.rcParams.update({"font.size": 8, "font.family": "sans-serif",
                     "font.sans-serif": ["Helvetica", "Arial", "Liberation Sans", "DejaVu Sans"],
                     "axes.edgecolor": INK2, "axes.linewidth": 0.6, "xtick.color": INK2,
                     "ytick.color": INK, "xtick.major.width": 0.6, "pdf.fonttype": 42})

# Node order (top to bottom), role label and whether the node has SMT enabled.
PANELS = {
    "xula": [("xula5504", "reference", False), ("xula5401", "flagged by screening", False),
             ("xula5304", "flagged by screening", False), ("xula5204", "SMT node", True)],
    "lusitania": [("s02r2b03", "control", False), ("s02r1b01", "reference, flagged", False),
                  ("s02r2b01", "SMT node", True)],
    "turgalium": [("aac104", "reference, SMT off", False), ("aac111", "excluded, SMT off", False),
                  ("acc102", "reference, SMT on", False), ("acc111", "excluded, SMT on", False)],
}
TITLES = {"xula": "Xula xula4 (2 × 56 cores)", "lusitania": "Lusitania us63 (2 × 8 cores)",
          "turgalium": "Turgalium cpu36c (2 × 18 cores)"}
XLIM = {"xula": 600, "lusitania": 65, "turgalium": 180}
XTICKS = {"xula": [0, 200, 400, 600], "lusitania": [0, 20, 40, 60], "turgalium": [0, 60, 120, 180]}


def stats(cluster, node):
    """Per job (sorted by job id): median and min-max (GB/s) of the effective
    rounds per placement. One job per node on Xula and Lusitania, two on Turgalium."""
    paths = sorted(glob.glob(str(data / cluster / "triad-binding" / f"{node}-*" / "manifest.csv")),
                   key=lambda p: int(p.split("/")[-2].split("-")[1]))
    assert len(paths) == (2 if cluster == "turgalium" else 1), (cluster, node, paths)
    jobs = []
    for p in paths:
        rows = [r for r in csv.DictReader(open(p)) if r["warmup"] == "0"]
        assert all(r["exit_code"] == "0" and r["verificacion"] == "OK" for r in rows)
        out = {"job": p.split("/")[-2].split("-")[1]}
        for pl in "AB":
            v = sorted(float(r["triad_MBps"]) / 1000 for r in rows if r["colocacion"] == pl)
            assert len(v) == 10, (node, pl, len(v))
            out[pl] = (st.median(v), v[0], v[-1])
        jobs.append(out)
    return jobs


fig, axes = plt.subplots(1, 3, figsize=(160 / 25.4, 40 / 25.4),
                         gridspec_kw={"wspace": 1.0, "width_ratios": [1, 1, 1]})
log = []
for ax, cluster in zip(axes, ("xula", "lusitania", "turgalium")):
    nodes = PANELS[cluster]
    ys = list(range(len(nodes) - 1, -1, -1))
    for y, (node, role, smt) in zip(ys, nodes):
        mk = "s" if smt else "o"
        for s in stats(cluster, node):
            for pl, dy, col, mfc in (("A", 0.17, OTH, "white"), ("B", -0.17, ACC, ACC)):
                med, lo, hi = s[pl]
                ax.plot([lo, hi], [y + dy, y + dy], color=col, lw=0.9, solid_capstyle="butt", zorder=2)
                ax.plot(med, y + dy, mk, ms=4.6, mfc=mfc, mec=col, mew=1.0, zorder=3)
                log.append(f"{cluster} {node} job {s['job']} {pl} median={med:.1f} min={lo:.1f} max={hi:.1f}")
    ax.set_yticks(ys); ax.set_yticklabels([f"{n}\n{r}" for n, r, _ in nodes], fontsize=7, color=INK)
    ax.set_ylim(-0.6, len(nodes) - 0.4)
    ax.set_xlim(0, XLIM[cluster])
    ax.set_xlabel("STREAM Triad (GB/s)")
    ax.text(0.0, 1.02, TITLES[cluster], transform=ax.transAxes, fontsize=8, fontweight="bold",
            va="bottom", color=INK)
    ax.grid(axis="x", color=GRID, lw=0.5); ax.set_axisbelow(True)
    for sp in ("top", "right", "left"):
        ax.spines[sp].set_visible(False)
    ax.tick_params(axis="y", length=0)
for ax, cluster in zip(axes, ("xula", "lusitania", "turgalium")):
    ax.set_xticks(XTICKS[cluster])
# v10m: wspace 0.62 -> 1.0 and width 140 -> 160 mm so that the y-labels of one panel
# no longer overlap the data of the panel to its left (verificacion-v10l M6).
# v10l: no in-figure legend; the caption describes the markers (open, default placement;
# filled, pinned; squares, the one-socket SMT nodes; two markers per row on Turgalium).
fig.savefig(dst / "fig-t53-pinned.pdf", bbox_inches="tight", metadata={"CreationDate": None, "ModDate": None})
fig.savefig(dst / "fig-t53-pinned.png", bbox_inches="tight", dpi=200)
print("\n".join(log))
