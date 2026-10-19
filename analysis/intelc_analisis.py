#!/usr/bin/env python3
"""Análisis de la fase B con intelc (L9b, jobs 84510-84522) frente a la fase B original.
P1 (D21) comparabilidad: intel/mlx de L9b vs intel/mlx de la matriz original (Δmediana <= 5 % e IQR solapados).
P2 efecto del compilador: intelc/mlx vs intel/mlx dentro de L9b (misma MPI, mismos nodos, rondas alternadas).
P3 posición de intelc/mlx frente a los pares de la fase B (directa y con puente por intel/mlx).
Criterio R1 (igual que h3_veredicto.py): distinguibles si |Δmediana|/menor > umbral y los IQR no se solapan.
Persona, 2026-10-09 (orden informes/ordenes/2026-10-09-T26-b9p07.md); informe: informes/2026-10-09-analisis-intelc.md.
Uso: python3 analysis/intelc_analisis.py . > resultado.json
     python3 analysis/intelc_analisis.py . --tabla   (resumen legible)"""
import sys, json, statistics as st
from pathlib import Path
REPO = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(REPO / "analysis"))
import fase_b_loader as B  # noqa: E402

L9B = {str(j) for j in range(84510, 84523)}
PARES_B = ["intel/mlx", "gcc/rc", "gcc/dc", "gcc/ud"]
UMBRALES = [0.03, 0.05, 0.10]

def q(xs, p):
    x = sorted(xs); k = (len(x) - 1) * p; f = int(k); c = min(f + 1, len(x) - 1)
    return x[f] + (x[c] - x[f]) * (k - f)
def summ(xs):
    if not xs: return {"n": 0}
    return {"n": len(xs), "mediana": st.median(xs), "q1": q(xs, .25), "q3": q(xs, .75),
            "iqr_rel": (q(xs, .75) - q(xs, .25)) / st.median(xs)}
def solapan(a, b): return not (a["q3"] < b["q1"] or b["q3"] < a["q1"])
def distinguible(a, b, u):
    lo, hi = sorted([a["mediana"], b["mediana"]])
    return (hi - lo) / lo > u and not solapan(a, b)

npb, hpcg = [], []
for jd in sorted((B.RAW / "phaseB").glob("faseB-*")):
    if jd.is_dir():
        n, h, _ = B.carga_job(jd); npb += n; hpcg += h

def serie(carga, talla, par, origen):
    if carga == "hpcg":
        job = "83403" if origen == "matriz" else "84522"
        return [r["gflops"] for r in hpcg if r["par"] == par and r["gflops"] is not None
                and str(r["job"]) == job and r["status"] == "efectiva"]
    ok = (lambda r: r["tipo"] == "matriz" and not r.get("reetiquetada")) if origen == "matriz" \
        else (lambda r: r["tipo"] == "intelc" and str(r["job"]) in L9B)
    return [r["time_s"] for r in npb if r["celda"] == f"{carga}-{talla}" and r["par"] == par
            and ok(r) and r["status"] == "efectiva" and r["time_s"]]

def pareado(carga, talla):
    """Cociente intelc/intel por ronda dentro de L9b (tiempo; en HPCG, GFLOP/s)."""
    if carga == "hpcg":
        rs = [r for r in hpcg if str(r["job"]) == "84522" and r["status"] == "efectiva" and r["gflops"]]
        key = lambda r: r["ronda"]; val = lambda r: r["gflops"]
    else:
        rs = [r for r in npb if r["tipo"] == "intelc" and str(r["job"]) in L9B and r["celda"] == f"{carga}-{talla}"
              and r["status"] == "efectiva" and r["time_s"]]
        key = lambda r: r["ronda"]; val = lambda r: r["time_s"]
    a = {key(r): val(r) for r in rs if r["par"] == "intelc/mlx"}
    b = {key(r): val(r) for r in rs if r["par"] == "intel/mlx"}
    rat = [a[k] / b[k] for k in a if k in b]
    return {"n": len(rat), "mediana": st.median(rat) if rat else None,
            "min": min(rat) if rat else None, "max": max(rat) if rat else None}

CELDAS = [(c, t) for c in ("ep", "ft", "cg", "mg") for t in ("1n", "2n", "4n", "8n")] + [("hpcg", "8n")]
res = []
for c, t in CELDAS:
    alto = c == "hpcg"
    m = {p: summ(serie(c, t, p, "matriz")) for p in PARES_B}
    i_intel = summ(serie(c, t, "intel/mlx", "intelc"))
    i_ic = summ(serie(c, t, "intelc/mlx", "intelc"))
    if not (i_intel["n"] and i_ic["n"] and m["intel/mlx"]["n"]):
        res.append({"celda": f"{c}-{t}", "falta": True}); continue
    d21 = (i_intel["mediana"] - m["intel/mlx"]["mediana"]) / m["intel/mlx"]["mediana"]
    comparable = abs(d21) <= 0.05 and solapan(i_intel, m["intel/mlx"])
    comp = (i_ic["mediana"] - i_intel["mediana"]) / i_intel["mediana"]   # >0: intelc más lento (tiempo) / más GFLOP/s (hpcg)
    mejor_comp = (comp > 0) if alto else (comp < 0)
    puente = i_ic["mediana"] * m["intel/mlx"]["mediana"] / i_intel["mediana"]
    cand = {p: m[p]["mediana"] for p in PARES_B if m[p]["n"]}
    cand_dir = dict(cand, **{"intelc/mlx": i_ic["mediana"]})
    cand_pte = dict(cand, **{"intelc/mlx": puente})
    ordena = lambda d: sorted(d, key=d.get, reverse=alto)
    mejor_b = ordena(cand)[0]
    res.append({
        "celda": f"{c}-{t}", "metrica": "GFLOP/s" if alto else "s",
        "matriz": m, "l9b_intel_mlx": i_intel, "l9b_intelc_mlx": i_ic,
        "d21_delta_intel": d21, "d21_comparable": comparable,
        "compilador_delta": comp, "compilador_favorece_intelc": mejor_comp,
        "compilador_distinguible": {f"{int(u*100)}": distinguible(i_ic, i_intel, u) for u in UMBRALES},
        "pareado_intelc_sobre_intel": pareado(c, t),
        "mejor_fase_b": mejor_b,
        "orden_directo": ordena(cand_dir), "orden_puente": ordena(cand_pte),
        "intelc_vs_mejor_fase_b_directo": (i_ic["mediana"] - cand[mejor_b]) / cand[mejor_b],
        "intelc_vs_mejor_fase_b_puente": (puente - cand[mejor_b]) / cand[mejor_b],
        "intelc_distinguible_de_mejor_fase_b_5": distinguible(i_ic, m[mejor_b], 0.05),
    })
if "--tabla" in sys.argv:
    print("celda | D21: Δ intel L9b vs fase B | comparable | ifx vs gfortran (Δ mediana) | distinguible al 5 % | cociente pareado | mejor fase B | orden directo | orden con puente")
    for r in res:
        if r.get("falta"): print(r["celda"], "| FALTA"); continue
        p = r["pareado_intelc_sobre_intel"]
        print(f'{r["celda"]} | {100*r["d21_delta_intel"]:+.1f} % | {"sí" if r["d21_comparable"] else "no"} | '
              f'{100*r["compilador_delta"]:+.1f} % | {"sí" if r["compilador_distinguible"]["5"] else "no"} | '
              f'{p["mediana"]:.3f} (n={p["n"]}) | {r["mejor_fase_b"]} | {" > ".join(r["orden_directo"])} | {" > ".join(r["orden_puente"])}')
else:
    json.dump(res, sys.stdout, indent=1, ensure_ascii=False)
