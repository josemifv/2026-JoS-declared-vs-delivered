#!/usr/bin/env python3
"""Veredicto formal de la hipótesis 3 (fase B de cpu112c).

Definición (E24, aceptada como D1): H3 se CONFIRMA si en alguna carga de la fase B el
mejor par de la fase A (OSU, R2: intel/mlx) es superado por otro par según R1; se
REFUTA si queda indistinguible del mejor en todas las cargas; los casos intermedios se
reportan por carga.
R1: distinguibles si |Δmediana| / mediana menor > umbral Y los IQR no se solapan.
Ámbito (3.ª auditoría, D14): FT, CG y HPCG a 8 nodos; FT, CG y MG a 1, 2 y 4 nodos.
EP queda fuera en todas las tallas (control, D14); MG-8n es no concluyente (~2 s).
Ambos se reportan aparte como sensibilidad. Sensibilidad R15: umbral 3/5/10 %.
Celdas válidas: tipo «matriz», no reetiquetadas, estado «efectiva» (rondas 2-11).
HPCG: job 83403 (83319 falló entero, exit 127).
Uso: python3 h3_veredicto.py <raíz del repositorio> > resultado.json
"""
import sys, json, statistics as st
from pathlib import Path

REPO = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(REPO / "analysis"))
import fase_b_loader as B  # noqa: E402

PARES = ["intel/mlx", "gcc/rc", "gcc/dc", "gcc/ud"]
MEJOR_FASE_A = "intel/mlx"
UMBRALES = [0.03, 0.05, 0.10]

def q(xs, p):
    x = sorted(xs); k = (len(x) - 1) * p; f = int(k); c = min(f + 1, len(x) - 1)
    return x[f] + (x[c] - x[f]) * (k - f)

def summ(xs):
    return {"n": len(xs), "mediana": st.median(xs), "q1": q(xs, .25), "q3": q(xs, .75),
            "iqr_rel": (q(xs, .75) - q(xs, .25)) / st.median(xs)}

def distinguible(a, b, u):
    lo, hi = sorted([a["mediana"], b["mediana"]])
    return (hi - lo) / lo > u and (a["q3"] < b["q1"] or b["q3"] < a["q1"])

npb, hpcg = [], []
for jd in sorted((REPO / "data/raw/phaseB").glob("faseB-*")):
    if jd.is_dir():
        n, h, _ = B.carga_job(jd); npb += n; hpcg += h

def serie(carga, talla, par):
    if carga == "hpcg":
        return [r["gflops"] for r in hpcg if r.get("par") == par and r.get("gflops") is not None
                and str(r.get("job")) == "83403" and r.get("status") == "efectiva"]
    return [r["time_s"] for r in npb if r.get("celda") == f"{carga}-{talla}" and r.get("par") == par
            and r.get("tipo") == "matriz" and not r.get("reetiquetada")
            and r.get("status") == "efectiva" and r.get("time_s")]

def evalua(carga, talla):
    alto = carga == "hpcg"   # GFLOP/s: mayor es mejor; tiempo: menor es mejor
    s = {p: summ(serie(carga, talla, p)) for p in PARES}
    s = {p: v for p, v in s.items() if v["n"] > 0}
    orden = sorted(s, key=lambda p: s[p]["mediana"], reverse=alto)
    mejor = orden[0]
    ref = s[MEJOR_FASE_A]
    out = {"carga": carga, "talla": talla, "metrica": "GFLOP/s" if alto else "s",
           "celdas": s, "orden": orden, "mejor": mejor,
           "rango_intel_mlx": orden.index(MEJOR_FASE_A) + 1}
    for u in UMBRALES:
        # ¿algún par supera a intel/mlx según R1?
        sup = [p for p in s if p != MEJOR_FASE_A
               and ((s[p]["mediana"] > ref["mediana"]) if alto else (s[p]["mediana"] < ref["mediana"]))
               and distinguible(s[p], ref, u)]
        out[f"supera_{int(u*100)}"] = sup
    d = (s[mejor]["mediana"] - ref["mediana"]) / ref["mediana"]
    out["dif_mejor_vs_intel_mlx"] = d
    return out

AMBITO = [("ft", "8n"), ("cg", "8n"), ("hpcg", "8n")] + \
         [(c, t) for t in ("1n", "2n", "4n") for c in ("ft", "cg", "mg")]
SENSIB = [("mg", "8n")] + [("ep", t) for t in ("1n", "2n", "4n", "8n")]
res = {"ambito": [evalua(c, t) for c, t in AMBITO],
       "fuera_de_ambito": [evalua(c, t) for c, t in SENSIB]}
for u in UMBRALES:
    k = f"supera_{int(u*100)}"
    conf = [f'{r["carga"]}-{r["talla"]}' for r in res["ambito"] if r[k]]
    res[f"veredicto_{int(u*100)}"] = {"cargas_donde_intel_mlx_es_superado": conf,
                                     "H3": "CONFIRMADA" if conf else "REFUTADA"}
json.dump(res, sys.stdout, indent=1, ensure_ascii=False)
