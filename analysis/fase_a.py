#!/usr/bin/env python3
"""Análisis de la fase A (transporte, OSU) — de data/raw/phaseA a data/derived/phaseA.

Regenera, sin intervención manual:
  - la tabla de celdas (mediana e IQR por par y prueba, n efectivo),
  - la selección R2 (puntuación oficial: posición media en las 4 métricas de análisis),
  - la sensibilidad de R2 con empates según R1 (rango medio, contra la cabeza del grupo),
  - el control de día D-B (inicio y fin de cada asignación).

Criterios (rules/RULES.md y rules/DEVIATIONS.md):
  - Etiquetado POR CONTENIDO de la salida, nunca por posición:
      gcc   -> lanes inter-node de UCX ("inter-node cfg#N tag(<tl>_mlx5/...)" o "tag(tcp/...)")
      intel -> "MPI startup(): libfabric provider: <prov>"
  - Celdas de la matriz identificadas por su rango de mensajes:
      pt2pt: "-m 8:4194304"; colectivas: "-m 262144".
      Humos ("-m 8192", "-m 1024") y control D-B ("-m 65536") quedan fuera de la matriz.
  - Ronda de cada run: marcadores "== RONDA k/N <iso>" del .out de cada asignación.
  - R1: la ronda 1 es calentamiento y no computa.
  - Una ronda incompleta en una asignación (p. ej. la ronda 6 de 83169, cortada por TIMEOUT)
    se conserva en el informe pero no computa (DEVIATIONS 2026-10-03).
  - Métricas de análisis (R2): latencia a 8 B, ancho de banda a 4 MiB, allreduce y alltoall a 64 KiB.
  - Cuartiles por interpolación lineal (equivalente a numpy.percentile por defecto).

Uso:  python3 analysis/fase_a.py [--raw DIR] [--out DIR]
Solo biblioteca estándar.
"""
import argparse
import bisect
import csv
import json
import re
import statistics
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

PT2PT_JOBS = ["faseA-pt2pt-83168"]
COLL_JOBS = ["faseA-colectivas-83169", "faseA-colectivas-83177", "faseA-colectivas-83178"]
MATRIX_FLAG = {"pt2pt": "8:4194304", "colectivas": "262144"}
CONTROL_FLAG = "65536"
ANALYSIS_SIZE = {"latency": "8", "bw": "4194304", "bibw": "4194304",
                 "allreduce": "65536", "alltoall": "65536"}
INTEL_PROV = {"mlx": "mlx", "verbs;ofi_rxm": "verbs", "tcp": "tcp"}
R1_DIFF = 0.05  # R1: diferencia relativa de medianas


def ts(s):
    s = s.strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    return datetime.fromisoformat(s).timestamp()


def quantile(xs, p):
    x = sorted(xs)
    k = (len(x) - 1) * p
    f = int(k)
    c = min(f + 1, len(x) - 1)
    return x[f] + (x[c] - x[f]) * (k - f)


def label(text):
    """Par stack/transporte deducido del contenido de la salida."""
    prov = re.findall(r"libfabric provider: (\S+)", text)
    if prov:
        return "intel/" + INTEL_PROV.get(prov[0], prov[0])
    lanes = sorted(set(re.findall(r"inter-node cfg#\d+ tag\(([a-z0-9]+?)(?:_mlx5)?/", text)))
    if len(lanes) == 1:
        return "gcc/" + lanes[0]
    if not lanes:
        return None
    return "gcc/" + "+".join(lanes)  # mezcla de lanes: se reporta tal cual


def value(text, size):
    v = re.findall(rf"^{re.escape(size)}\s+([\d.]+)", text, re.M)
    return float(v[0]) if v else None


def round_markers(out_file):
    marks = []
    # "== RONDA k/N <iso>" (fase A) o "== RONDA k <iso>" (ligero cpu36c)
    for line in out_file.read_text(errors="replace").splitlines():
        m = re.match(r"== RONDA (\d+)(?:/\d+)? (\S+)", line.strip())
        if m:
            marks.append((ts(m.group(2)), int(m.group(1))))
    return sorted(marks)


def load_block(raw, jobs, block):
    runs, controls = [], []
    for job in jobs:
        jid = job.split("-")[-1]
        outs = list(raw.glob(f"*-{jid}.out"))
        marks = round_markers(outs[0]) if outs else []
        mts = [m[0] for m in marks]
        for line in (raw / job / "commands.jsonl").read_text().splitlines():
            c = json.loads(line)
            cmd = " ".join(c["cmd"])
            m = re.search(r"osu_(latency|bibw|bw|allreduce|alltoall)\b", cmd)
            if not m:
                continue
            test, flag = m.group(1), c["cmd"][-1]
            text = (raw / job / "outputs" / f"{c['out_hash']}.out").read_text(errors="replace")
            rec = {"job": jid, "ts": c["ts"], "test": test, "exit": c["exit_code"],
                   "pair": label(text), "value": value(text, ANALYSIS_SIZE[test]), "hash": c["out_hash"]}
            if flag == CONTROL_FLAG and test == "allreduce":
                controls.append(rec)
            elif flag == MATRIX_FLAG[block]:
                i = bisect.bisect_right(mts, ts(c["ts"])) - 1
                rec["round"] = marks[i][1] if i >= 0 else None
                runs.append(rec)
    return runs, controls


def mark_effective(runs):
    # Completitud POR JOB: en cpu36c cada asignación cubre combinaciones distintas
    # (p. ej. intel/verbs solo), así que la ronda se compara con las celdas que su
    # propia asignación debe tener (unión de lo observado en ese job). En fase A
    # (una asignación con todos los pares) el criterio coincide con el anterior.
    job_cells = {}
    for r in runs:
        job_cells.setdefault(r["job"], set()).add((r["pair"], r["test"]))
    per_job_round = {}
    for r in runs:
        per_job_round.setdefault((r["job"], r["round"]), set()).add((r["pair"], r["test"]))
    for r in runs:
        complete = per_job_round[(r["job"], r["round"])] == job_cells[r["job"]]
        r["status"] = ("calentamiento" if r["round"] == 1 else
                       "ronda incompleta" if not complete else
                       "fallo" if r["exit"] != 0 or r["value"] is None else "efectiva")
    return runs


def summarize(runs):
    table = {}
    for r in runs:
        if r["status"] == "efectiva":
            table.setdefault((r["pair"], r["test"]), []).append(r["value"])
    rows = []
    for (pair, test), xs in sorted(table.items()):
        rows.append({"par": pair, "prueba": test, "mensaje": ANALYSIS_SIZE[test], "n": len(xs),
                     "mediana": statistics.median(xs), "q1": quantile(xs, .25), "q3": quantile(xs, .75)})
    return rows


def r1_distinguishable(a, b):
    lo, hi = sorted([a["mediana"], b["mediana"]])
    differ = (hi - lo) / lo > R1_DIFF
    disjoint = a["q3"] < b["q1"] or b["q3"] < a["q1"]
    return differ and disjoint


METRICS = [("latency", False), ("bw", True), ("allreduce", False), ("alltoall", False)]


def r2(rows, ties=False):
    by = {(r["par"], r["prueba"]): r for r in rows}
    pairs = sorted({r["par"] for r in rows})
    ranks = {p: [] for p in pairs}
    for test, higher_better in METRICS:
        cand = sorted([by[(p, test)] for p in pairs if (p, test) in by],
                      key=lambda r: r["mediana"], reverse=higher_better)
        if not ties:
            for i, r in enumerate(cand, 1):
                ranks[r["par"]].append(i)
            continue
        i = 0
        while i < len(cand):  # grupos contra la cabeza (sin encadenar)
            j = i + 1
            while j < len(cand) and not r1_distinguishable(cand[i], cand[j]):
                j += 1
            mid = (i + 1 + j) / 2
            for r in cand[i:j]:
                ranks[r["par"]].append(mid)
            i = j
    score = {p: sum(v) / len(v) for p, v in ranks.items() if v}
    order = sorted(score, key=score.get)
    best3 = order[:3]
    nontcp = [p for p in order if not p.endswith("/tcp")]
    worst = nontcp[-1]
    selected = best3 + ([worst] if worst not in best3 else [])
    return {"puntuacion": score, "rangos": ranks, "seleccion": selected}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--raw", type=Path, default=REPO / "data/raw/phaseA")
    ap.add_argument("--out", type=Path, default=REPO / "data/derived/phaseA")
    ap.add_argument("--pt2pt-jobs", type=str, default=",".join(PT2PT_JOBS),
                    help="directorios de asignaciones pt2pt bajo --raw (por defecto: fase A)")
    ap.add_argument("--coll-jobs", type=str, default=",".join(COLL_JOBS),
                    help="directorios de asignaciones de colectivas bajo --raw (por defecto: fase A)")
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)

    p_runs, p_ctrl = load_block(a.raw, a.pt2pt_jobs.split(","), "pt2pt")
    c_runs, c_ctrl = load_block(a.raw, a.coll_jobs.split(","), "colectivas")
    runs = mark_effective(p_runs) + mark_effective(c_runs)
    unlabeled = [r for r in runs if r["pair"] is None]
    rows = summarize(runs)

    with open(a.out / "runs.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["job", "round", "ts", "pair", "test", "value", "exit", "status", "hash"])
        w.writeheader()
        for r in runs:
            w.writerow({k: r.get(k) for k in w.fieldnames})
    with open(a.out / "celdas.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    with open(a.out / "control_db.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["job", "ts", "pair", "value"])
        w.writeheader()
        for r in sorted(p_ctrl + c_ctrl, key=lambda r: (r["job"], r["ts"])):
            w.writerow({k: r[k] for k in w.fieldnames})
    result = {"oficial": r2(rows), "empates_R1": r2(rows, ties=True),
              "runs_sin_etiqueta": len(unlabeled),
              "estado_runs": {s: sum(1 for r in runs if r["status"] == s)
                              for s in ("efectiva", "calentamiento", "ronda incompleta", "fallo")}}
    (a.out / "r2.json").write_text(json.dumps(result, indent=2, ensure_ascii=False))

    print(f"runs de matriz: {len(runs)}  {result['estado_runs']}  sin etiqueta: {len(unlabeled)}")
    for r in rows:
        print(f"{r['par']:12s} {r['prueba']:9s} n={r['n']:2d} mediana={r['mediana']:.6g} "
              f"IQR=[{r['q1']:.6g}, {r['q3']:.6g}]")
    for k in ("oficial", "empates_R1"):
        s = result[k]
        print(f"R2 {k}: " + ", ".join(f"{p} {v:.2f}" for p, v in sorted(s['puntuacion'].items(), key=lambda x: x[1]))
              + f"  -> selección {s['seleccion']}")


if __name__ == "__main__":
    main()
