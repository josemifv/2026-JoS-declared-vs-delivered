#!/usr/bin/env python3
"""Regenera data/derived/controles-db.csv y controles-db-resumen.csv desde data/raw.

Celdas de control D-B (osu_allreduce -m 65536, pila gcc por defecto) al inicio y
fin de cada asignación (DEVIATIONS 2026-10-03, P-2/P-5; decisión 2026-10-05 de
usarlas como vigilancia de la variabilidad a corto plazo).

Fuentes en data/raw:
  - fase B y ligero: <dir de asignación>/control-{inicio,fin}.log (tabla OSU).
  - fase A: los controles viven DENTRO de commands.jsonl (no hay control-*.log):
    comandos osu_allreduce con "-m 65536"; el valor se lee del output referenciado
    por out_hash (outputs/<hash>.out; rebasado de rutas del clúster a data/raw).

Uso: python3 analysis/controles_db.py
"""
from __future__ import annotations

import csv
import json
import re
import statistics as st
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RAW = REPO / "data" / "raw"
OUT = REPO / "data" / "derived"
SIZE = "65536"


def _local(p: str) -> Path:
    """Rebase de rutas absolutas del clúster al espejo data/raw del portátil."""
    for marker, sub in (("/cc/raw/", ""), ("/scratch/discovery/", "discovery/turgalium/"),
                        ("/scratch/probe_level1/", "probe_level1/")):
        if marker in p:
            rest = p.split(marker, 1)[1]
            if marker == "/cc/raw/" and rest.startswith("equivalence/"):
                rest = "equivalence/turgalium/" + rest.split("equivalence/", 1)[1]
            return RAW.joinpath(sub, rest)
    return Path(p)


def valor_osu(path: Path) -> float | None:
    """Latencia media (µs) de la fila de 64 KiB de una tabla OSU."""
    try:
        for line in open(path, errors="ignore"):
            c = line.split()
            if len(c) >= 2 and c[0] == SIZE:
                return float(c[1])
    except OSError:
        pass
    return None


def particion_y_cfg(ruta_rel: str, np_hint: int | None) -> tuple[str, int]:
    """(partición, ranks del control) — 2ª auditoría: los ranks van SIEMPRE del
    -np REAL del comando (del commands.jsonl de la asignación); el fallback por
    partición mezclaba humos de 64/128 ranks con la matriz de 512."""
    part = "cpu36c" if ruta_rel.startswith("ligero") else "cpu112c"
    return part, np_hint or 0


TIPOS = {"83304": "humo", "83693": "humo", "83702": "humo",   # humos (fase B y v5.2)
         "83305": "cancelado",                                  # cancelado en calentamiento
         "83365": "abortado"}                                   # lanzador roto (DEVIATIONS 2026-10-04)


def tipo_job(job: str, ruta_rel: str) -> str:
    """3ª auditoría (punto 2): humos/cancelados/abortados fuera del resumen."""
    if job in TIPOS:
        return TIPOS[job]
    return "humo" if "humo" in ruta_rel else "matriz"


def np_de_control(dir_asig: Path) -> int | None:
    """-np del osu_allreduce -m 65536 de esta asignación (del commands.jsonl)."""
    cj = dir_asig / "commands.jsonl"
    if not cj.exists():
        return None
    for line in open(cj, errors="ignore"):
        try:
            j = json.loads(line)
        except Exception:
            continue
        cmd = " ".join(j.get("cmd", []))
        if "allreduce" in cmd and SIZE in cmd:
            return next((int(x) for x in j["cmd"] if x.isdigit()), None)
    return None


def main() -> None:
    filas = []  # (job, control, valor, ts, ruta_rel, part, cfg)

    # fase B y ligero: control-*.log (los ranks van del commands.jsonl de la asignación)
    for f in sorted(RAW.rglob("control-*.log")):
        rel = str(f.relative_to(RAW))
        m = re.search(r"(\d{5,})", f.parent.name) or re.search(r"(\d{5,})", rel)
        job = m.group(1) if m else "?"
        part, cfg = particion_y_cfg(rel, np_de_control(f.parent))
        filas.append({"job": job, "control": f.stem.replace("control-", ""), "valor": valor_osu(f),
                      "ts": "", "ruta": rel, "part": part, "cfg": cfg,
                      "tipo": tipo_job(job, rel)})

    # fase A: controles dentro de commands.jsonl (todos los allreduce 65536 del dir)
    for cj in sorted((RAW / "phaseA").glob("*/commands.jsonl")):
        hits = []
        for line in open(cj, errors="ignore"):
            try:
                j = json.loads(line)
            except Exception:
                continue
            cmd = " ".join(j.get("cmd", []))
            if "allreduce" in cmd and SIZE in cmd:
                np_ = next((int(x) for x in j["cmd"] if x.isdigit()), None)
                hits.append((j, np_))
        if not hits:
            continue
        rel = str(cj.relative_to(RAW))
        m = re.search(r"(\d{5,})", rel)
        job = m.group(1) if m else "?"
        # 2ª auditoría: con UN solo control (83169, TIMEOUT P-5) se cuenta UNA vez
        pares = (("inicio", hits[0]),) if len(hits) == 1 else (("inicio", hits[0]), ("fin", hits[-1]))
        for etiqueta, (j, np_) in pares:
            p = _local(j.get("out_path", ""))
            part, cfg = particion_y_cfg(rel, np_)
            filas.append({"job": job, "control": etiqueta, "valor": valor_osu(p) if p.exists() else None,
                          "ts": j.get("ts", "")[:16], "ruta": rel, "part": part, "cfg": cfg,
                          "tipo": tipo_job(job, rel)})

    OUT.mkdir(exist_ok=True)
    with open(OUT / "controles-db.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["job", "control", "valor_64KiB_us", "ts", "ruta", "particion", "ranks_control", "tipo"])
        for r in sorted(filas, key=lambda x: (x["ts"] or "9", x["job"])):
            w.writerow([r["job"], r["control"], "" if r["valor"] is None else r["valor"],
                        r["ts"], r["ruta"], r["part"], r["cfg"], r["tipo"]])

    grp = defaultdict(list)
    for r in filas:
        if r["valor"] is not None and r["tipo"] == "matriz":  # el resumen: solo matriz
            grp[(r["part"], r["cfg"])].append(r["valor"])
    with open(OUT / "controles-db-resumen.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["particion", "ranks_control", "n", "mediana_us", "iqr_us", "cv_pct", "min_us", "max_us"])
        for (part, cfg), vals in sorted(grp.items()):
            med, mean = st.median(vals), st.mean(vals)
            sd = st.stdev(vals) if len(vals) > 1 else 0.0
            q = st.quantiles(vals, n=4) if len(vals) >= 4 else (min(vals), med, max(vals))
            w.writerow([part, cfg, len(vals), round(med, 2), f"{q[0]:.2f}-{q[2]:.2f}",
                        round(sd / mean * 100, 2), round(min(vals), 2), round(max(vals), 2)])
    print(f"controles-db.csv: {len(filas)} controles; resumen: {len(grp)} grupos")


if __name__ == "__main__":
    main()
