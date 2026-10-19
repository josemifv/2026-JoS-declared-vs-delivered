#!/usr/bin/env python3
"""declared_real.py - tabla de discrepancias declarado/real (DISCOVERY.md seccion 1 y 5).

Lee los JSON por nodo de data/raw/discovery/<cluster>/ y el slurm.json, y genera
la tabla de discrepancias D1/D2/D3 por particion:

  D1. Declarado vs. real  - scontrol (o fuente declarada del atributo) frente a
      lo observado en el nodo, dentro de un mismo nodo.
  D2. Real vs. real       - nodos de la misma particion con valores reales distintos.
  D3. Declarado vs. declarado - slurm.json (particion) frente a la suma de lo
      declarado por nodo (TRES cpu, memoria maxima por nodo).

Ademas, si existe clusters/modulos_declarados/<cluster>.json, compara las versiones
que declaran los modulos de cada pila con las reales medidas en el descubrimiento
(atributos *_version de software/) o con la evidencia de ejecucion que se pase
(--evidence, JSON en linea); las filas van en report["versiones"] y en
discrepancias_versiones.md (D1-versiones).

Salidas (con --out-dir, como fingerprint.py):
  discrepancias.json                    machine-readable, por particion
  discrepancias_<particion>.md          tabla markdown por particion
  discrepancias_versiones.md            versiones declaradas vs. reales por pila (si aplica)

Uso:
  python3 discovery/declared_real.py --cluster <nombre> [--partition P]
        [--raw-dir DIR] [--out-dir DIR]

Variables de entorno que consume:
  DISCOVERY_RAW   raw-dir por defecto si no se pasa --raw-dir
  DISCOVERY_OUT   out-dir por defecto si no se pasa --out-dir
"""

import argparse
import datetime
import json
import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def canon(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def load_nodes(raw_dir, partition):
    nodes = []
    for name in sorted(os.listdir(raw_dir)):
        if not name.endswith(".json") or name == "slurm.json":
            continue
        with open(os.path.join(raw_dir, name), "r", encoding="utf-8") as fh:
            doc = json.load(fh)
        if doc.get("role") != "node":
            continue
        if partition and doc.get("partition") != partition:
            continue
        nodes.append(doc)
    return nodes


def load_software(raw_dir, partition):
    """JSONs de software/ (uno por nodo, role 'login' por recolectarse en login)."""
    sw_dir = os.path.join(raw_dir, "software")
    docs = []
    if not os.path.isdir(sw_dir):
        return docs
    for name in sorted(os.listdir(sw_dir)):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(sw_dir, name), "r", encoding="utf-8") as fh:
            doc = json.load(fh)
        if partition and doc.get("partition") != partition:
            continue
        docs.append(doc)
    return docs


def fmt(value, limit=80):
    """Valor en una sola linea y acotado; la fidelidad completa queda en discrepancias.json."""
    text = value if isinstance(value, str) else canon(value)
    text = " ".join(text.split())
    if len(text) > limit:
        text = text[: limit - 3] + "..."
    return text


def d1_rows(nodes):
    """D1: declarado observable y real observable difieren en un mismo nodo."""
    rows = []
    for doc in nodes:
        node = doc.get("node")
        for key, attr in sorted(doc.get("attributes", {}).items()):
            dec = attr.get("declared") or {}
            real = attr.get("real") or {}
            if not (dec.get("observable") and real.get("observable")):
                continue
            if canon(dec.get("value")) == canon(real.get("value")):
                continue
            rows.append({
                "node": node, "attribute": key,
                "declared": dec.get("value"), "real": real.get("value"),
            })
    return rows


def d2_rows(nodes):
    """D2: dentro de una particion, el valor real difiere entre nodos."""
    by_value = {}
    for doc in nodes:
        for key, attr in sorted(doc.get("attributes", {}).items()):
            real = attr.get("real") or {}
            if not (real.get("observable") and real.get("value") is not None):
                continue
            by_value.setdefault(key, {})
            by_value[key].setdefault(canon(real.get("value")), {"value": real.get("value"), "nodes": []})
            by_value[key][canon(real.get("value"))]["nodes"].append(doc.get("node"))
    rows = []
    for key, groups in sorted(by_value.items()):
        if len(groups) < 2:
            continue
        variants = sorted(groups.values(), key=lambda g: (-len(g["nodes"]), canon(g["value"])))
        rows.append({"attribute": key, "variants": variants})
    return rows


def d3_rows(slurm_doc, nodes):
    """D3: slurm.json (particion) frente a lo declarado por nodo."""
    rows = []
    parts = {p.get("PartitionName"): p for p in slurm_doc.get("partitions", [])}
    by_part = {}
    for doc in nodes:
        by_part.setdefault(doc.get("partition"), []).append(doc)
    for part, docs in sorted(by_part.items(), key=lambda kv: str(kv[0])):
        info = parts.get(str(part))
        if not info:
            rows.append({"partition": part, "check": "particion en slurm.json",
                         "slurm_json": None, "nodes_declared": "ausente"})
            continue
        # cpus declarados por nodo (suma) frente a TRES/TotalCPUs de la particion
        cpu_attr = [d["attributes"].get("logical_cpus_online", {}).get("declared", {}) for d in docs]
        totals = [c.get("value") for c in cpu_attr if c.get("observable") and isinstance(c.get("value"), int)]
        if totals and info.get("TotalCPUs", "").isdigit():
            if sum(totals) != int(info["TotalCPUs"]):
                rows.append({"partition": part, "check": "suma de CPUs por nodo vs TotalCPUs",
                             "slurm_json": info["TotalCPUs"], "nodes_declared": str(sum(totals))})
        # memoria: MaxMemPerNode (MiB) frente a RealMemory declarado por nodo (MiB)
        mem_attr = [d["attributes"].get("memory_total_kb", {}).get("declared", {}) for d in docs]
        reals = [m.get("value") for m in mem_attr if m.get("observable") and isinstance(m.get("value"), int)]
        max_mem = info.get("MaxMemPerNode", "")
        if reals and max_mem.isdigit():
            distinct = sorted({round(v / 1024) for v in reals})
            for mib in distinct:
                if mib > int(max_mem):
                    rows.append({"partition": part, "check": "RealMemory por nodo vs MaxMemPerNode",
                                 "slurm_json": max_mem + "M", "nodes_declared": str(mib) + "M"})
    return rows


# Atributo de software/ donde se mide cada componente de las pilas declaradas.
VERSION_ATTR_PREFIX = {
    "gcc": "gcc_version",
    "openmpi": "openmpi_version",
    "ucx": "ucx_version",
    "intelmpi": "intelmpi_version",
    "libfabric": "libfabric_version",
    "icx": "icx_version",
}


def load_declared(cluster):
    """Pilas y versiones declaradas; None si no hay fichero para el cluster."""
    path = os.path.join(REPO_ROOT, "clusters", "modulos_declarados", "%s.json" % cluster)
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def version_rows(software_docs, declared, evidence=None):
    """D1-versiones: version declarada por el modulo frente a la medida.

    La real se busca en los atributos *_version[@modN] de software/; si el
    descubrimiento no la capturo, se admite evidencia de ejecucion
    (--evidence: {"componente": {"value": ..., "source": ...}}).
    coincide: True si la version declarada aparece en la cadena real.
    """
    evidence = evidence or {}
    rows = []
    for pila, info in sorted(declared.get("pilas", {}).items()):
        sufijo = info.get("attr_sufijo", "")
        for comp, declared_v in sorted((info.get("versiones_declaradas") or {}).items()):
            if declared_v is None:
                continue
            prefix = VERSION_ATTR_PREFIX.get(comp, comp + "_version")
            real_val, source = None, None
            for doc in software_docs:
                for key, attr in sorted(doc.get("attributes", {}).items()):
                    if not key.startswith(prefix):
                        continue
                    if key != prefix + sufijo:
                        continue
                    real = attr.get("real") or {}
                    if real.get("observable") and real.get("value"):
                        real_val = real["value"]
                        source = "%s:%s" % (doc.get("node"), key)
                        break
                if real_val is not None:
                    break
            if real_val is None and comp in evidence:
                real_val = evidence[comp].get("value")
                source = evidence[comp].get("source", "evidencia de ejecucion")
            rows.append({
                "pila": pila, "componente": comp, "declarado": declared_v,
                "real": real_val, "fuente": source,
                "coincide": (isinstance(real_val, str) and declared_v in real_val)
                            if real_val is not None else None,
            })
    return rows


def render_versions_md(rows, cluster):
    lines = [
        "# D1-versiones: versiones declaradas vs. reales - %s" % cluster,
        "",
        "Generado por `discovery/declared_real.py` el %s; fuente declarada:" % utc_now(),
        "`clusters/modulos_declarados/%s.json` (espejo de la seccion 'Entorno de" % cluster,
        "de software' de `clusters/%s.md`)." % cluster,
        "",
        "| Pila | Componente | Declarado | Real | Fuente | Coincide |",
        "|---|---|---|---|---|---|",
    ]
    for r in rows:
        coincide = {True: "si", False: "**NO**", None: "no observable"}[r["coincide"]]
        lines.append("| %s | %s | `%s` | `%s` | %s | %s |" % (
            r["pila"], r["componente"], fmt(r["declarado"], 24), fmt(r["real"], 48),
            fmt(r["fuente"], 48) if r["fuente"] else "-", coincide))
    lines.append("")
    return "\n".join(lines)


def render_md(partition, d1, d2, d3):
    lines = [
        "# Discrepancias declarado/real - particion %s" % partition,
        "",
        "Generado por `discovery/declared_real.py` el %s (DISCOVERY.md secciones 1 y 5)." % utc_now(),
        "",
        "## D1. Declarado vs. real (por nodo)",
        "",
    ]
    if not d1:
        lines.append("Sin discrepancias D1 observables.")
    else:
        lines += ["| Nodo | Atributo | Declarado | Real |", "|---|---|---|---|"]
        for r in d1:
            lines.append("| %s | `%s` | `%s` | `%s` |" % (r["node"], r["attribute"],
                                                          fmt(r["declared"]), fmt(r["real"])))
    lines += ["", "## D2. Real vs. real (entre nodos de la particion)", ""]
    if not d2:
        lines.append("Sin discrepancias D2: valor real uniforme en todos los atributos observados.")
    else:
        for r in d2:
            lines.append("- **%s**:" % r["attribute"])
            for v in r["variants"]:
                lines.append("  - `%s` -> %s" % (fmt(v["value"]), ", ".join(v["nodes"])))
    lines += ["", "## D3. Declarado vs. declarado (slurm.json frente a nodos)", ""]
    if not d3:
        lines.append("Sin discrepancias D3 detectables con las fuentes disponibles.")
    else:
        lines += ["| Particion | Comprobacion | slurm.json | Nodos (declarado) |", "|---|---|---|---|"]
        for r in d3:
            lines.append("| %s | %s | `%s` | `%s` |" % (r.get("partition", "-"), r.get("check"),
                                                        fmt(r.get("slurm_json")), fmt(r.get("nodes_declared"))))
    lines.append("")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Tabla de discrepancias D1/D2/D3 (DISCOVERY.md secciones 1 y 5).")
    parser.add_argument("--cluster", required=True)
    parser.add_argument("--partition", default=None, help="limitar a una particion")
    parser.add_argument("--raw-dir", default=None)
    parser.add_argument("--out-dir", default=None)
    parser.add_argument("--declared", default=None,
                        help="JSON de versiones declaradas (por defecto clusters/modulos_declarados/<cluster>.json)")
    parser.add_argument("--evidence", default=None,
                        help='JSON en linea con versiones reales no capturadas por el descubrimiento, p ej. \'{"ucx": {"value": "1.20.0", "source": "..."}}\'')
    parser.add_argument("--slurm-json", default=None,
                        help="slurm.json a consumir (por defecto <raw-dir>/slurm.json; admite recolectas como slurm-<fecha>.json)")
    args = parser.parse_args(argv)

    raw_dir = args.raw_dir or os.environ.get("DISCOVERY_RAW") or os.path.join(
        REPO_ROOT, "data", "raw", "discovery", args.cluster)
    if not os.path.isdir(raw_dir):
        sys.stderr.write("declared_real: no existe %s\n" % raw_dir)
        return 1
    slurm_path = args.slurm_json or os.path.join(raw_dir, "slurm.json")
    slurm_doc = {}
    if os.path.isfile(slurm_path):
        with open(slurm_path, "r", encoding="utf-8") as fh:
            slurm_doc = json.load(fh)

    nodes = load_nodes(raw_dir, args.partition)
    if not nodes:
        sys.stderr.write("declared_real: no hay JSON de nodo en %s\n" % raw_dir)
        return 1

    by_part = {}
    for doc in nodes:
        by_part.setdefault(doc.get("partition"), []).append(doc)

    declared = None
    if args.declared:
        with open(args.declared, "r", encoding="utf-8") as fh:
            declared = json.load(fh)
    else:
        declared = load_declared(args.cluster)
    evidence = json.loads(args.evidence) if args.evidence else None
    software_docs = load_software(raw_dir, args.partition)

    report = {"cluster": args.cluster, "generated_at": utc_now(), "partitions": {}}
    for part, docs in sorted(by_part.items(), key=lambda kv: str(kv[0])):
        d1, d2 = d1_rows(docs), d2_rows(docs)
        d3 = d3_rows(slurm_doc, docs)
        report["partitions"][str(part)] = {"d1": d1, "d2": d2, "d3": d3, "nodes": len(docs)}
    if declared:
        report["versiones"] = version_rows(software_docs, declared, evidence)

    if not args.out_dir:
        json.dump(report, sys.stdout, indent=2, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0

    os.makedirs(args.out_dir, exist_ok=True)
    with open(os.path.join(args.out_dir, "discrepancias.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    for part in report["partitions"]:
        safe = str(part).replace("/", "_")
        with open(os.path.join(args.out_dir, "discrepancias_%s.md" % safe), "w", encoding="utf-8") as fh:
            p = report["partitions"][part]
            fh.write(render_md(part, p["d1"], p["d2"], p["d3"]))
    if declared:
        with open(os.path.join(args.out_dir, "discrepancias_versiones.md"), "w", encoding="utf-8") as fh:
            fh.write(render_versions_md(report["versiones"], args.cluster))
    sys.stderr.write("declared_real: %d particiones en %s\n" % (len(report["partitions"]), args.out_dir))
    return 0


if __name__ == "__main__":
    sys.exit(main())
