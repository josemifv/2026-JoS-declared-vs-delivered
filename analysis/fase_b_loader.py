#!/usr/bin/env python3
"""Cargador del análisis de fase B (DEVIATIONS [D] auditorías 2026-10-05).

De data/raw/phaseB/faseB-* (y ligero/ft8n-*) a filas de análisis. SIN veredicto
de la hipótesis 3 (pendiente de revisión del cargador por la persona).

Reglas (2ª y 3ª auditoría):
- La MÉTRICA NPB se lee de outputs/<out_hash>.out (cmdlog), emparejando con el
  manifiesto 1:1 por ORDEN (el manifiesto se escribe en orden de ejecución y el
  cmdlog va ordenado por ts), verificando en cada pareja (kernel, pila, ranks).
  El transporte no figura en la argv del cmdlog (ni UCX_TLS ni FI_PROVIDER en
  toda la fase B): no se puede usar para emparejar, y el par del manifiesto es
  la fuente. Los run.log de los rundirs compartidos de 83314-83407 (v4 sin
  transporte) quedaron SOBRESCRITOS por ud: no se usan como fuente de datos.
- HPCG: el resultado va en HPCG-Benchmark_*.txt del rundir (hallazgo 83403).
  Los rundirs gcc comparten directorio entre transportes (3 txts): asignación
  txt↔par por el ORDEN DEL MANIFIESTO (= orden de ejecución), con
  len(filas)==len(txts) avisando si no cuadra (sin truncar).
- tipo: matriz | humo (83304, 83693, 83702) | cancelado (83305) | abortado
  (83365). Se EXCLUYEN del análisis: SALTADA, humos, cancelado/abortado y las
  filas stream de fase B.
- status: ronda 1 = calentamiento (R1).
- relabel: fase B por (job, celda) y ft8n por (job, "ft-"+par) — ambos
  reetiquetan y marcan `reetiquetada=True` (excluidas de H3/fichas/E-f).

Uso:  python3 analysis/fase_b_loader.py            # tabla + resumen a stderr
"""
from __future__ import annotations

import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import relabel  # noqa: E402

RAW = REPO / "data/raw"
# Transporte observado POR CONTENIDO del output (4ª revisión, punto 1):
#   gcc/UCX: «tag(rc_mlx5/mlx5_0:1)» en las líneas de lanes; intel/libfabric:
#   «libfabric provider: mlx» (o «verbs;ofi_rxm»). Discordancia con el par del
#   manifiesto → aviso y fila EXCLUIDA.
TRANS_UCX_RE = re.compile(r"tag\(([a-z]+)_mlx5", re.I)
TRANS_FI_RE = re.compile(r"libfabric provider:\s*([a-z_;]+)", re.I)
# Lanes intra-nodo impresas por UCX (tag(self/memory knem/…): sin _mlx5
TRANS_INTRA_RE = re.compile(r"tag\((self|knem|shm|posix|sysv)[/:)]", re.I)
# Lanes INTRA-NODO de UCX (celdas 1n: sin comunicación de red, UCX usa self/knem
# aunque UCX_TLS pida rc): su presencia sola NO es discordancia — el transporte
# de red sencillamente no aparece. Discordancia = hay lanes de red y falta el
# esperado.
INTRA_LANES = {"self", "knem", "shm", "posix", "sysv", "memory"}
GFLOPS_RE = re.compile(r"GFLOP/s rating of\s*=\s*=?\s*([0-9.]+)", re.I)
VALID_RE = re.compile(r"HPCG\s+result\s+is\s+(VALID|INVALID)", re.I)
TIME_RE = re.compile(r"Time in seconds\s*=\s*([0-9.]+)")
MOPS_RE = re.compile(r"Mop/s total\s*=\s*([0-9.]+)", re.I)
HUMOS = {"83304", "83693", "83702"}
CANCELADOS = {"83305"}
ABORTADOS = {"83365"}


def _local(p: Path) -> Path:
    """Rutas absolutas del clúster (…/cc/raw/…) → el espejo data/raw del portátil."""
    s = str(p)
    if "/cc/raw/" in s:
        rest = s.split("/cc/raw/", 1)[1]
        if rest.startswith("equivalence/"):
            rest = "equivalence/turgalium/" + rest.split("equivalence/", 1)[1]
        return RAW / rest
    return p


def tipo_job(job: str, ruta: str) -> str:
    if job in HUMOS:
        return "humo"
    if job in CANCELADOS:
        return "cancelado"
    if job in ABORTADOS:
        return "abortado"
    return "humo" if "humo" in ruta else "matriz"


def carga_cmdlog(job_dir: Path):
    """Comandos NPB/HPCG del cmdlog: [(ts, kernel, pila, trans, np, out_path)]."""
    out = []
    cj = job_dir / "commands.jsonl"
    if not cj.exists():
        return out
    for line in open(cj, errors="ignore"):
        try:
            j = json.loads(line)
        except Exception:
            continue
        cmd = " ".join(j.get("cmd", []))
        m = re.search(r"/npb/([a-z]+)/[a-z]+/(ep|ft|cg|mg)\.D\.x", cmd)
        if m:
            pila, kernel = m.group(1), m.group(2)
            trans = (re.search(r"UCX_TLS=([a-z_;,]+)", cmd).group(1).split(",")[0]
                     if "UCX_TLS=" in cmd else
                     (re.search(r"FI_PROVIDER[= ]+([a-z_;]+)", cmd).group(1).split(";")[0]
                      if "FI_PROVIDER" in cmd else "?"))
            np_ = next((int(x) for x in j["cmd"] if x.isdigit()), 0)
            out.append({"ts": j["ts"], "kernel": kernel, "pila": pila, "trans": trans,
                        "np": np_, "out": _local(Path(j["out_path"])) if j.get("out_path") else None,
                        "exit": j.get("exit_code")})
    return sorted(out, key=lambda x: x["ts"])


_OUT_CACHE: dict[str, tuple[float | None, float | None, str | None]] = {}


def lee_out(out_path) -> tuple[float | None, float | None, str | None]:
    """(Time in seconds, Mop/s total, transportes observados) del output real.
    Transportes = todos los tag(X_mlx5) de UCX y/o el provider de libfabric,
    separados por coma; None = sin patrón en el contenido (no verificable).
    multi-TLS (anclas: rc_mlx5,ud_mlx5,sm) produce varios: se verifican por
    PERTENENCIA del transporte esperado al conjunto."""
    key = str(out_path)
    if key in _OUT_CACHE:
        return _OUT_CACHE[key]
    res = (None, None, None)
    p = Path(out_path) if out_path else None
    if p is not None and p.exists():
        txt = p.read_text(errors="replace")
        t, m = TIME_RE.search(txt), MOPS_RE.search(txt)
        obs = {x.lower() for x in TRANS_UCX_RE.findall(txt)}
        obs |= {x.lower() for x in TRANS_INTRA_RE.findall(txt)}
        mf = TRANS_FI_RE.search(txt)
        if mf:
            obs.add(mf.group(1).lower())
        trans = ",".join(sorted(obs)) if obs else None
        res = (float(t.group(1)) if t else None, float(m.group(1)) if m else None, trans)
    _OUT_CACHE[key] = res
    return res


def metrica_npb(out_path) -> tuple[float | None, float | None]:
    """(Time in seconds, Mop/s total) de la salida NPB real (outputs por hash)."""
    t, m, _ = lee_out(out_path)
    return t, m


def carga_job(job_dir: Path):
    """Filas de una asignación faseB-*: NPB+HPCG ya emparejadas y etiquetadas."""
    man = job_dir / "manifest.csv"
    if not man.exists():
        return [], [], []
    rel_ruta = str(job_dir.relative_to(RAW))
    cmds = carga_cmdlog(job_dir)
    filas = list(csv.DictReader(open(man)))
    tipo = ("intelc" if any(f.get("par", "").startswith("intelc/") for f in filas)
            else tipo_job(job_dir.name.split("-")[-1], rel_ruta))
    npb, hpcg, avisos = [], [], []

    # --- NPB: manifiesto (orden de ejecución) ↔ cmdlog (orden ts), 1:1
    npb_rows = [f for f in filas
                if not f.get("celda", "").startswith(("stream", "hpcg"))]
    pend = list(cmds)
    verificados = 0   # transporte de red observado por contenido y = esperado
    excl_trans = 0    # discordancia manifiesto vs contenido
    intranodo = 0     # solo lanes intra-nodo (1n): red no observable en contenido
    total_runs = 0    # filas ejecutadas emparejadas (sin SALTADA)
    for f in npb_rows:
        if f["verificacion"] == "SALTADA":
            npb.append({"job": f["job"], "grupo": f["grupo"], "tipo": tipo,
                        "celda": f["celda"], "par": f["par"], "ranks": f["ranks"],
                        "ronda": f["ronda"], "exit_code": f["exit_code"],
                        "verificacion": f["verificacion"],
                        "time_s": None, "mops": None, "out": ""})
            continue
        kernel = f["celda"].split("-")[0]
        pila = f["par"].split("/", 1)[0]
        try:
            ranks = int(f["ranks"])
        except (TypeError, ValueError):
            ranks = None
        i = next((k for k, c in enumerate(pend)
                  if c["kernel"] == kernel and c["pila"] == pila
                  and (ranks is None or c["np"] in (0, ranks))), None)
        c = pend.pop(i) if i is not None else None
        if c is None:
            avisos.append(f"{job_dir.name}: {f['celda']} {f['par']} r{f['ronda']} — fila sin comando cmdlog")
            continue
        total_runs += 1
        t, mops, trans_obs = lee_out(c["out"])
        # 4ª revisión (punto 1): transporte por CONTENIDO vs par del manifiesto
        if trans_obs is not None:
            esperado = f["par"].split("/", 1)[1].lower()
            obs_set = {o for o in trans_obs.split(",")}
            if any(o == esperado or o.startswith(esperado) or esperado.startswith(o)
                   for o in obs_set):
                verificados += 1
            elif not (obs_set - INTRA_LANES):
                # 1n: solo lanes intra-nodo — el transporte de red no aparece
                intranodo += 1
            else:
                avisos.append(f"{job_dir.name}: {f['celda']} {f['par']} r{f['ronda']} — transporte observado «{trans_obs}» sin «{esperado}»: fila EXCLUIDA")
                excl_trans += 1
                continue
        npb.append({"job": f["job"], "grupo": f["grupo"], "tipo": tipo,
                    "celda": f["celda"], "par": f["par"], "ranks": f["ranks"],
                    "ronda": f["ronda"], "exit_code": c["exit"],
                    "verificacion": f["verificacion"],
                    "time_s": t, "mops": mops,
                    "out": str(c["out"]) if c["out"] else ""})
    for c in pend:  # comandos NPB del cmdlog sin fila en el manifiesto
        avisos.append(f"{job_dir.name}: comando cmdlog sin fila — {c['kernel']} {c['pila']}/{c['trans']} np={c['np']}")
    if total_runs:
        print(f"TRANSPORTE-POR-CONTENIDO {job_dir.name}: {verificados}/{total_runs} verificados, "
              f"{intranodo} intranodo (1n, red no observable), {excl_trans} excluidos por discordancia", file=sys.stderr)
    npb = relabel.aplica(npb)
    for r in npb:   # [D]: ronda 1 = calentamiento
        r["status"] = "calentamiento" if r["ronda"] == "1" else "efectiva"
        if r["verificacion"] == "SALTADA":
            r["status"] = "saltada"

    # --- HPCG: rundir compartido por transportes (gcc: 3 txts); check de conteo
    hpcg_filas = [f for f in filas if f.get("celda", "").startswith("hpcg")]
    por_rundir = defaultdict(list)
    for f in hpcg_filas:
        por_rundir[_local(Path(f["runlog"]).parent)].append(f)
    for rd, fs in sorted(por_rundir.items()):
        # filas falladas (exit_code≠0, p.ej. 83319: exit 127, wrapper v4 por ruta
        # relativa) no producen txt: se emiten como filas sin medida, sin aviso
        vivos = [f for f in fs if str(f.get("exit_code", "0")) == "0"]
        falladas = [f for f in fs if str(f.get("exit_code", "0")) != "0"]
        if falladas:
            avisos.append(f"{job_dir.name}: {rd.name} — {len(falladas)} run(s) con exit_code≠0 (sin txt que buscar)")
        txts = sorted(rd.glob("HPCG-Benchmark_*.txt"))
        if len(txts) != len(vivos):
            avisos.append(f"{job_dir.name}: {rd.name} — {len(vivos)} filas vivas vs {len(txts)} txts (NO se trunca)")
            continue
        for f, txtp in zip(vivos, txts):
            txt = txtp.read_text(errors="replace")
            v, g = VALID_RE.search(txt), GFLOPS_RE.search(txt)
            hpcg.append({"job": f["job"], "tipo": tipo, "par": f["par"],
                         "ronda": f["ronda"], "ranks": f["ranks"],
                         "exit_code": f["exit_code"], "txt": txtp.name,
                         "valid": v.group(1) if v else "?",
                         "gflops": float(g.group(1)) if g else None,
                         "status": "calentamiento" if f["ronda"] == "1" else "efectiva"})
        for f in falladas:
            hpcg.append({"job": f["job"], "tipo": tipo, "par": f["par"],
                         "ronda": f["ronda"], "ranks": f["ranks"],
                         "exit_code": f["exit_code"], "txt": "",
                         "valid": "FALLO", "gflops": None,
                         "status": "calentamiento" if f["ronda"] == "1" else "efectiva"})
    return npb, hpcg, avisos


def carga_ft8n(ligero_dir: Path):
    """FT-8n del ligero cpu36c: celda construida como f"ft-{par}" para el relabel."""
    man = ligero_dir / "manifest.csv"
    if not man.exists():
        return [], []
    filas = list(csv.DictReader(open(man)))
    cmds = carga_cmdlog(ligero_dir)
    rows = []
    pend = list(cmds)
    verificados = excl_trans = total_runs = intranodo = 0
    for f in filas:  # manifiesto en orden de ejecución ↔ cmdlog por ts, 1:1
        celda = f"ft-{f['par']}"
        if f["verificacion"] == "SALTADA":
            rows.append({"job": f["job"], "tipo": tipo_job(f["job"], str(ligero_dir)),
                         "celda": celda, "par": f["par"], "ronda": f["ronda"],
                         "exit_code": f["exit_code"], "verificacion": f["verificacion"],
                         "time_s": None, "mops": None, "ranks": f["ranks"]})
            continue
        pila = f["par"].split("/", 1)[0]
        try:
            ranks = int(f["ranks"])
        except (TypeError, ValueError):
            ranks = None
        i = next((k for k, c in enumerate(pend)
                  if c["kernel"] == "ft" and c["pila"] == pila
                  and (ranks is None or c["np"] in (0, ranks))), None)
        c = pend.pop(i) if i is not None else None
        if c is None:
            print(f"AVISO {ligero_dir.name}: {celda} r{f['ronda']} — fila sin comando cmdlog", file=sys.stderr)
            continue
        total_runs += 1
        t, mops, trans_obs = lee_out(c["out"])
        if trans_obs is not None:   # 4ª revisión (punto 1), igual que en fase B
            esperado = f["par"].split("/", 1)[1].lower()
            obs_set = set(trans_obs.split(","))
            if any(o == esperado or o.startswith(esperado) or esperado.startswith(o)
                   for o in obs_set):
                verificados += 1
            elif not (obs_set - INTRA_LANES):
                intranodo += 1
            else:
                print(f"AVISO {ligero_dir.name}: {celda} r{f['ronda']} — transporte observado «{trans_obs}» sin «{esperado}»: fila EXCLUIDA", file=sys.stderr)
                excl_trans += 1
                continue
        rows.append({"job": f["job"], "tipo": tipo_job(f["job"], str(ligero_dir)),
                     "celda": celda, "par": f["par"], "ronda": f["ronda"],
                     "exit_code": c["exit"], "verificacion": f["verificacion"],
                     "time_s": t, "mops": mops, "ranks": f["ranks"]})
    for c in pend:
        print(f"AVISO {ligero_dir.name}: comando cmdlog sin fila — {c['pila']}/{c['trans']} np={c['np']}", file=sys.stderr)
    if total_runs:
        print(f"TRANSPORTE-POR-CONTENIDO {ligero_dir.name}: {verificados}/{total_runs} verificados, "
              f"{intranodo} intranodo (1n, red no observable), {excl_trans} excluidos por discordancia", file=sys.stderr)
    rows = relabel.aplica(rows)
    for r in rows:
        r["status"] = "calentamiento" if r["ronda"] == "1" else "efectiva"
    return rows, []


def main() -> None:
    todo_np, todo_hpcg = [], []
    for jd in sorted((RAW / "phaseB").glob("faseB-*")):
        if jd.is_dir():
            npb, hpcg, avisos = carga_job(jd)
            todo_np += npb
            todo_hpcg += hpcg
            for a in avisos:
                print(f"AVISO {a}", file=sys.stderr)
    for jd in sorted((RAW / "ligero").glob("ft8n-*")):
        if jd.is_dir():
            rows, _ = carga_ft8n(jd)
            todo_np += rows
    # exclusión por tipo/estado (3c): SALTADA, humos, cancelado/abortado ya llevan tipo
    utiles = [r for r in todo_np if r["status"] != "saltada"]
    print(f"# filas: {len(todo_np)} (+{len(todo_hpcg)} HPCG) | útiles para análisis: "
          f"{len(utiles)} | reetiquetadas: {sum(1 for r in todo_np if r.get('reetiquetada'))}",
          file=sys.stderr)
    # tabla txt↔par (revisión de la persona) + filas útiles de muestra
    for r in todo_hpcg:
        print(f"HPCG,{r['job']},{r['par']},{r['ronda']},{r['txt']},{r['valid']},{r['gflops']},{r['status']}")
    for r in utiles[:12]:
        print(f"NPB,{r['job']},{r['tipo']},{r['celda_label']},{r['par']},{r['ronda']},"
              f"{r['status']},Time={r['time_s']},Mops={r['mops']}")


if __name__ == "__main__":
    main()
