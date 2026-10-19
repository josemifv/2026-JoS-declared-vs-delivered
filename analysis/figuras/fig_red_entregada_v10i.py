#!/usr/bin/env python3
"""Figura: red instalada frente a red que recibe el MPI del usuario, en los tres clústeres.

v10i (versión corta): cuarta fila con los dos pares de nodos normales de Lusitania
(seguimiento T53 parte B, 18 oct 2026, sin s02r1b01): latencia 8 B 1.26 y 1.73 us,
ancho de banda 4 MiB 4730 y 4729 MB/s (medianas de 10 rondas efectivas, ucx:rc_verbs
en las 44 ejecuciones). Fuente: carril-c data/raw/lusitania/lat-normales/<par>-<job>/
(commit 1cd5c059); valores calculados por el coordinador (T53-resultados.md); los
datos brutos no estan en figrepo, por lo que se escriben como constantes.

(a) Ancho de banda punto a punto con mensajes de 4 MiB (osu_bw) frente a la tasa del
enlace instalado; (b) latencia con 8 B (osu_latency), escala logarítmica. En los dos
paneles se marca como referencia el resultado de TCP en Turgalium (gcc/tcp, fase A).

Entradas (rutas relativas al repo):
  data/derived/phaseA/celdas.csv                         Turgalium cpu112c, fase A, n = 10
  informes/2026-10-17-analisis-xula/resultados.csv       Xula xula4, L15/L15b, elegibles (corte 17 oct)
  data/raw/lusitania/us63/equivalence/medida-*/lat-1/    us63, L16b, primera ronda
Salida: paper/figures/fig-red.pdf
Uso: python3 fig_red_entregada_v10i.py <repo> [<out dir>]
"""
import csv, glob, statistics as st, sys
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

repo = Path(sys.argv[1]).resolve()
dst = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else repo / "paper/figures"
dst.mkdir(parents=True, exist_ok=True)
ACC, WARN, OTH, INK, INK2, GRID = "#2a78d6", "#c2410c", "#8a8984", "#0b0b0b", "#52514e", "#e4e3df"
plt.rcParams.update({"font.size": 8, "font.family": "sans-serif",
                     "font.sans-serif": ["Helvetica", "Arial", "Liberation Sans", "DejaVu Sans"],
                     "axes.edgecolor": INK2, "axes.linewidth": 0.6, "xtick.color": INK2,
                     "ytick.color": INK, "xtick.major.width": 0.6, "pdf.fonttype": 42})

# Turgalium: fase A, mediana de 10 rondas.
cel = {(r["par"], r["prueba"], r["mensaje"]): float(r["mediana"])
       for r in csv.DictReader((repo / "data/derived/phaseA/celdas.csv").open())}
t_bw, t_lat = cel[("gcc/rc", "bw", "4194304")] / 1000, cel[("gcc/rc", "latency", "8")]
tcp_bw, tcp_lat = cel[("gcc/tcp", "bw", "4194304")] / 1000, cel[("gcc/tcp", "latency", "8")]

# Xula: mediana de las medidas elegibles de la prueba de equivalencia (todas por TCP).
xr = [r for r in csv.DictReader((repo / "informes/2026-10-17-analisis-xula/resultados.csv").open())
      if r["record_type"] == "run" and r["eligible"] == "1"]
x_bw = st.median(float(r["value"]) for r in xr if r["metric"] == "bandwidth_4MiB") / 1000
x_lat = st.median(float(r["value"]) for r in xr if r["metric"] == "latency_8B")
assert {r["transport_observed"] for r in xr if r["metric"] in ("latency_8B", "bandwidth_4MiB")} == {"btl:tcp"}


def osu_value(path, size):
    """Valor de osu_latency u osu_bw para un tamaño, o None."""
    for line in Path(path).read_text(errors="replace").splitlines():
        f = line.split()
        if len(f) == 2 and f[0] == str(size):
            try:
                return float(f[1])
            except ValueError:
                pass
    return None


# us63: primera ronda de los 11 pares de L16b (latencia; el ancho de banda no se midió).
# L16c (EQ01, un par, tres rondas efectivas) se cita en el texto, no en la figura.
lat = [osu_value(p, 8) for p in glob.glob(str(repo / "data/raw/lusitania/us63/equivalence/medida-*/lat-1/run.log"))]
u_lat, u_bw, u_note = st.median(v for v in lat if v is not None), None, "L16b, round 1"
# us63, pares normales (T53 parte B): s02r1b09+s02r1b17 1.26 us / 4730 MB/s;
# s02r2b03+s02r2b05 1.73 us / 4729 MB/s (medianas, n = 10). Se dibuja la barra de
# latencia hasta el mayor de los dos pares y se rotulan ambos valores.
N_LAT = (1.26, 1.73); N_BW = (4730 / 1000, 4729 / 1000)

rows = [  # etiqueta, enlace instalado (GB/s), entregado bw, entregado lat, transporte
    ("Turgalium cpu112c\nHDR 200 Gb/s", 25.0, t_bw, t_lat, "UCX rc_mlx5", ACC),
    ("Xula xula4\nHDR 200 Gb/s", 25.0, x_bw, x_lat, "TCP (module UCX lacks IB)", WARN),
    # us63: puerto 1 ACTIVO a 40 Gb/s (4X FDR10) = 5,0 GB/s; el puerto 2 esta DOWN y su
    # fichero sysfs marca 10 Gb/s (valor por defecto de un puerto sin conectar). Fuente:
    # data/raw/lusitania/us63/discovery/outputs/540212458f9d...out y 92b34d6078bc...out;
    # el MPI usa rc_verbs/mlx4_0:1 (lat-1/run.log). Corregido en v10g (antes se habian
    # invertido los puertos al leer listas ordenadas del JSON).
    ("Lusitania us63, screening pairs\nFDR10 40 Gb/s; all pairs share flagged node", 5.0, u_bw, u_lat, "UCX rc_verbs", WARN),
    ("Lusitania us63, normal pairs\nFDR10 40 Gb/s; follow-up, 18 Oct", 5.0, max(N_BW), max(N_LAT), "UCX rc_verbs", ACC),
]
Y = [3, 2, 1, 0]
fig, (a1, a2) = plt.subplots(1, 2, figsize=(129 / 25.4, 48 / 25.4), sharey=True,
                             gridspec_kw={"wspace": 0.08})
for y, (lab, link, bw, lat, tr, c) in zip(Y, rows):
    a1.barh(y, link, height=0.62, facecolor="white", edgecolor=INK2, lw=0.7, zorder=2)
    if bw is not None:
        a1.barh(y, bw, height=0.62, color=c, zorder=3)
        a1.text(link + 0.6, y, f"{bw:.1f} of {link:.0f}" + (" (both pairs)" if y == 0 else ""),
                va="center", fontsize=7, color=INK)
    else:
        a1.text(link + 0.6, y, "not measured", va="center", fontsize=7, color=INK2, style="italic")
    a2.barh(y, lat, height=0.62, color=c, zorder=3)
    if y == 0:
        a2.text(lat * 1.15, y, f"{N_LAT[0]:.2f} and {N_LAT[1]:.2f} µs  {tr} (two pairs)", va="center", fontsize=7, color=INK)
    else:
        a2.text(lat * 1.15, y, f"{lat:.1f} µs  {tr}", va="center", fontsize=7, color=INK)
a1.axvline(tcp_bw, color=INK2, lw=0.8, ls=(0, (2, 2)), zorder=4)
# label beside the dashed line, not across it (review v10i item A.8)
a1.text(tcp_bw + 0.7, 3.5, "TCP on Turgalium", fontsize=6.5, color=INK2, ha="left", va="bottom")
a2.axvline(tcp_lat, color=INK2, lw=0.8, ls=(0, (2, 2)), zorder=4)
a2.text(tcp_lat * 1.12, 3.5, "TCP on Turgalium", fontsize=6.5, color=INK2, ha="left", va="bottom")
a1.set_xlim(0, 34); a1.set_xlabel("Bandwidth, 4 MiB (GB/s); outline = installed link")
a2.set_xscale("log"); a2.set_xlim(0.5, 3000); a2.set_xlabel("Latency, 8 B (µs), log scale")
a2.set_xticks([1, 10, 100]); a2.set_xticklabels(["1", "10", "100"]); a2.minorticks_off()
a1.set_yticks(Y); a1.set_yticklabels([r[0] for r in rows], fontsize=7); a1.set_ylim(-0.6, 3.95)
for ax, t in ((a1, "(a)"), (a2, "(b)")):
    ax.grid(axis="x", color=GRID, lw=0.5); ax.set_axisbelow(True)
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.tick_params(axis="y", length=0)
    ax.text(0.0, 1.02, t, transform=ax.transAxes, fontsize=8, fontweight="bold", va="bottom")
fig.savefig(dst / "fig-red.pdf", bbox_inches="tight")
fig.savefig(dst / "fig-red.png", bbox_inches="tight", dpi=200)
print(f"turgalium bw={t_bw:.2f} lat={t_lat:.2f}; tcp bw={tcp_bw:.2f} lat={tcp_lat:.2f}; "
      f"xula bw={x_bw:.2f} lat={x_lat:.2f}; us63 bw={u_bw} lat={u_lat:.2f} ({u_note}); "
      f"us63 normal pairs lat={N_LAT} bw={N_BW}")
