#!/usr/bin/env python3
"""Validación E-f del protocolo ligero en cpu112c (DEVIATIONS 2026-10-02 E-f; unificación 2026-10-04).

Simula el protocolo ligero con la SUBMUESTRA de las 5 primeras repeticiones efectivas
(rondas 2-6) de la fase A (OSU) y de FT-8n (fase B), y compara su recomendación con
la de la matriz completa (10 efectivas, rondas 2-11) en cada carga a 8 nodos.

Cargas de comparación (principal): FT, CG y HPCG a 8 nodos. EP (control, D14) y MG-8n
(no concluyente, ~2 s) solo en el análisis de sensibilidad.
Concordancia: el par recomendado por el ligero es el mejor de la matriz completa en la
carga o no es distinguible de él según R1 (medianas > umbral Y IQR disjuntos).
Sensibilidad R15: umbral 3 %, 5 % y 10 %.
Uso: python3 analysis/ef_validacion.py . > data/derived/ef/ef_resultado.json
"""
import sys, json, statistics as st
from pathlib import Path

REPO = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(REPO / "analysis"))
import fase_a as A          # noqa: E402
import fase_b_loader as B   # noqa: E402

def q(xs, p):
    x = sorted(xs); k = (len(x) - 1) * p; f = int(k); c = min(f + 1, len(x) - 1)
    return x[f] + (x[c] - x[f]) * (k - f)

def summ(xs):
    return {"n": len(xs), "mediana": st.median(xs), "q1": q(xs, .25), "q3": q(xs, .75)}

def distinguible(a, b, umbral):
    lo, hi = sorted([a["mediana"], b["mediana"]])
    return (hi - lo) / lo > umbral and (a["q3"] < b["q1"] or b["q3"] < a["q1"])

# ---------- Fase A: R2 con la submuestra (rondas 2-6) y con todo (2-11) ----------
raw_a = REPO / "data/raw/phaseA"
p_runs, _ = A.load_block(raw_a, A.PT2PT_JOBS, "pt2pt")
c_runs, _ = A.load_block(raw_a, A.COLL_JOBS, "colectivas")
runs_a = A.mark_effective(p_runs) + A.mark_effective(c_runs)
def r2_de(rounds):
    sub = [dict(r) for r in runs_a if r["status"] == "efectiva" and r["round"] in rounds]
    for r in sub: r["status"] = "efectiva"
    rows = A.summarize(sub)
    return rows, A.r2(rows), A.r2(rows, ties=True), sub
rows5, r2_5, r2t_5, sub5 = r2_de(set(range(2, 7)))
rows10, r2_10, r2t_10, sub10 = r2_de(set(range(2, 12)))
n_por_celda_5 = sorted({r["n"] for r in rows5})

# ---------- Fase B: celdas 8n válidas (no reetiquetadas, matriz, efectivas) ----------
npb, hpcg = [], []
for jd in sorted((REPO / "data/raw/phaseB").glob("faseB-*")):
    if jd.is_dir():
        n, h, _ = B.carga_job(jd); npb += n; hpcg += h
def serie(carga, par, rondas, metrica="time_s"):
    if carga == "hpcg":
        xs = [r["gflops"] for r in hpcg if r.get("par") == par and r.get("gflops") is not None
              and int(r["ronda"]) in rondas and str(r.get("job")) == "83403"]
        return xs
    xs = [r[metrica] for r in npb if r.get("celda") == f"{carga}-8n" and r.get("par") == par
          and r.get("tipo") == "matriz" and not r.get("reetiquetada") and r.get(metrica)
          and r.get("status") in ("efectiva",) and int(r["ronda"]) in rondas]
    return xs
PARES_B = ["intel/mlx", "gcc/rc", "gcc/dc", "gcc/ud"]
MEJOR_ALTO = {"hpcg": True}   # en el resto, tiempo: menor es mejor

def mejor(carga, rondas):
    s = {p: summ(serie(carga, p, rondas)) for p in PARES_B if serie(carga, p, rondas)}
    alto = MEJOR_ALTO.get(carga, False)
    best = (max if alto else min)(s, key=lambda p: s[p]["mediana"])
    return best, s

# ---------- Recomendación del ligero: pares R2 (submuestra) → mejor en FT-8n (submuestra)
sel5 = r2_5["seleccion"]
ft_disp = [p for p in sel5 if serie("ft", p, set(range(2, 7)))]
ft5 = {p: summ(serie("ft", p, set(range(2, 7)))) for p in ft_disp}
rec_ligero = min(ft5, key=lambda p: ft5[p]["mediana"])

# ---------- Concordancia con la matriz completa ----------
res = {"seleccion_R2_ligero": sel5, "seleccion_R2_ligero_empates": r2t_5["seleccion"],
       "seleccion_R2_completa": r2_10["seleccion"], "n_por_celda_faseA_ligero": n_por_celda_5,
       "pares_sin_FT8n_en_faseB": [p for p in sel5 if p not in ft_disp],
       "FT8n_ligero": ft5, "recomendacion_ligero": rec_ligero, "cargas": {}}
for carga in ["ft", "cg", "hpcg", "mg", "ep"]:
    best, s = mejor(carga, set(range(2, 12)))
    fila = {"mejor_completa": best, "resumen": s, "concordancia": {}}
    for u in (0.03, 0.05, 0.10):
        if rec_ligero not in s:
            fila["concordancia"][f"{int(u*100)}%"] = "sin dato"; continue
        ok = rec_ligero == best or not distinguible(s[rec_ligero], s[best], u)
        fila["concordancia"][f"{int(u*100)}%"] = "concuerda" if ok else "NO concuerda"
    res["cargas"][carga] = fila
print(json.dumps(res, indent=1, ensure_ascii=False, default=float))
