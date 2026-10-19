#!/usr/bin/env python3
"""fingerprint.py - fingerprint y subparticiones reales (DISCOVERY.md seccion 4).

Lee los JSON por nodo de data/raw/discovery/<cluster>/<nodo>.json (salida de
collect_node.py), construye el fingerprint (hash de los atributos F
normalizados), agrupa los nodos en clases de equivalencia (subparticiones
reales), indica en que atributos difieren las subparticiones y genera las listas
de nodos para --nodelist (seccion 4.4).

Por DEVIATIONS 2026-09-25 (fingerprint): el fingerprint de cada particion usa
solo los atributos F observables en TODOS los nodos de esa particion; los
excluidos se registran con su motivo, porque comparar hashes con campos nulos
fabricaria subparticiones espurias por falta de observabilidad.

Uso:
  python3 discovery/fingerprint.py --cluster <nombre>
        [--raw-dir DIR] [--out-dir DIR] [--include-login]

  Sin --out-dir solo imprime el resumen JSON por stdout. Con --out-dir escribe:
    subpartitions.json   subparticiones, diferencias y anotacion de --constraint
    nodelists.json       mapa subparticion -> lista de nodos (y fichero .txt)
    nodelist_<i>.txt     lista de nodos separada por comas (formato --nodelist)

Variables de entorno que consume:
  DISCOVERY_RAW   raw-dir por defecto si no se pasa --raw-dir
  DISCOVERY_OUT   out-dir por defecto si no se pasa --out-dir (si esta definida)

Por defecto se excluye el nodo de login (no es una subparticion de computo);
con --include-login se incluye.
"""

import argparse
import datetime
import hashlib
import json
import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def canon_json(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def fingerprint_of(values):
    return hashlib.sha256(canon_json(values).encode("utf-8")).hexdigest()


def load_nodes(raw_dir, include_login):
    nodes = []
    for name in sorted(os.listdir(raw_dir)):
        if not name.endswith(".json") or name == "slurm.json":
            continue
        with open(os.path.join(raw_dir, name), "r", encoding="utf-8") as fh:
            doc = json.load(fh)
        if doc.get("role") == "slurm":
            continue
        if doc.get("role") == "login" and not include_login:
            continue
        nodes.append(doc)
    return nodes


def observable(doc, key):
    """Cierto si el valor real del atributo es observable en el nodo."""
    real = doc.get("attributes", {}).get(key, {}).get("real", {})
    return bool(real.get("observable")) and real.get("value") is not None


# Normalización de atributos F antes del hash (DEVIATIONS 2026-09-25 y 2026-09-26,
# memoria): valores cuyo ruido de contabilidad no implica hardware distinto no deben
# separar subparticiones. Memoria: GiB enteros en bloques de 64 (caso 2026-09-26:
# 1007/1008 GiB en cpu112c y 188/189 GiB en cpu36c son contabilidad).
NORMALIZERS = {
    "memory_total_kb": lambda v: round(float(v) / 1048576 / 64) * 64,
}


def common_features(doc):
    declared = doc.get("attributes", {}).get("slurm_features", {}).get("declared", {})
    if declared.get("observable"):
        return set(declared.get("value") or [])
    return set()


def build(nodes):
    # Agrupa por particion y fija, por particion, los atributos F observables en
    # todos sus nodos (DEVIATIONS 2026-09-25, fingerprint).
    partitions = {}
    for doc in nodes:
        node = doc.get("node") or "(desconocido)"
        partitions.setdefault(doc.get("partition"), {})[node] = doc

    used_by_part, excluded_by_part = {}, {}
    for part, docs in sorted(partitions.items(), key=lambda kv: str(kv[0])):
        seen, all_keys = set(), []
        for doc in docs.values():
            keys = doc.get("fingerprint_attrs") or doc.get("fingerprint_keys") or []
            for key in keys:
                if key not in seen:
                    seen.add(key)
                    all_keys.append(key)
        used, excluded = [], {}
        for key in all_keys:
            bad = sorted(n for n, d in docs.items() if not observable(d, key))
            if not bad:
                used.append(key)
            elif len(bad) == len(docs):
                excluded[key] = {"reason": "no observable en toda la partición (limitación del descubrimiento)"}
            else:
                excluded[key] = {"reason": "no observable en: " + ", ".join(bad)}
        used_by_part[part] = used
        excluded_by_part[part] = excluded

    groups = {}
    meta = {}
    for doc in nodes:
        node = doc.get("node") or "(desconocido)"
        part = doc.get("partition")
        keys = used_by_part[part]
        values = {}
        attrs = doc.get("attributes", {})
        for key in keys:
            real = attrs.get(key, {}).get("real", {})
            value = real.get("value") if real.get("observable") else None
            if key in NORMALIZERS and value is not None:
                value = NORMALIZERS[key](value)
            values[key] = value
        fp = fingerprint_of(values)
        meta[node] = {
            "doc": doc, "keys": keys, "values": values, "fingerprint": fp,
            "stored_fingerprint": doc.get("fingerprint"),
            "partition": part,
            "role": doc.get("role"),
        }
        groups.setdefault(fp, []).append(node)

    order = sorted(groups.items(), key=lambda kv: (-len(kv[1]), kv[0]))
    subpartitions = []
    for idx, (fp, members) in enumerate(order):
        members = sorted(members)
        common = None
        if members:
            common = set.intersection(*[common_features(meta[n]["doc"]) for n in members])
        subpartitions.append({
            "id": idx,
            "fingerprint": fp,
            "size": len(members),
            "nodes": members,
            "nodelist": ",".join(members),
            "constraint_candidate": ",".join(sorted(common)) if common else None,
        })

    majority = subpartitions[0]["fingerprint"] if subpartitions else None
    maj_values = meta[subpartitions[0]["nodes"][0]]["values"] if subpartitions else {}

    attributes_by_value = {}
    if nodes:
        for key in meta[subpartitions[0]["nodes"][0]]["keys"]:
            by_val = {}
            for node, info in meta.items():
                sv = canon_json(info["values"].get(key))
                by_val.setdefault(sv, []).append(node)
            attributes_by_value[key] = {
                val: sorted(members) for val, members in sorted(by_val.items())
            }

    for sp in subpartitions:
        if sp["fingerprint"] == majority:
            sp["differs_from_majority"] = {}
            continue
        sample = meta[sp["nodes"][0]]
        maj_keys = set(meta[subpartitions[0]["nodes"][0]]["keys"])
        diffs = {}
        for key in sample["keys"]:
            if key not in maj_keys:
                continue  # no comparable contra la mayoria (distinta particion)
            val = sample["values"].get(key)
            maj = maj_values.get(key)
            if canon_json(val) != canon_json(maj):
                diffs[key] = {"value": val, "majority": maj}
        sp["differs_from_majority"] = diffs

    partitions_info = {
        str(part): {
            "nodes": sorted(partitions[part]),
            "fingerprint_attrs_used": used_by_part[part],
            "fingerprint_attrs_excluded": excluded_by_part[part],
        }
        for part in sorted(partitions, key=str)
    }
    return {
        "cluster": nodes[0].get("cluster") if nodes else None,
        "generated_at": utc_now(),
        "fingerprint_attrs": meta[subpartitions[0]["nodes"][0]]["keys"] if nodes else [],
        "partitions": partitions_info,
        "majority": majority,
        "subpartitions": subpartitions,
        "attributes_by_value": attributes_by_value,
        "nodes": {n: {"fingerprint": i["fingerprint"],
                      "partition": i["partition"],
                      "role": i["role"],
                      "stored_fingerprint_matches": i["stored_fingerprint"] in (None, i["fingerprint"])}
                  for n, i in meta.items()},
    }


def write_outputs(report, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "subpartitions.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    nodelists = {}
    for sp in report["subpartitions"]:
        fname = "nodelist_%d.txt" % sp["id"]
        with open(os.path.join(out_dir, fname), "w", encoding="utf-8") as fh:
            fh.write(sp["nodelist"] + "\n")
        nodelists[str(sp["id"])] = {
            "fingerprint": sp["fingerprint"],
            "size": sp["size"],
            "nodes": sp["nodes"],
            "nodelist": sp["nodelist"],
            "constraint_candidate": sp["constraint_candidate"],
            "file": fname,
        }
    with open(os.path.join(out_dir, "nodelists.json"), "w", encoding="utf-8") as fh:
        json.dump(nodelists, fh, indent=2, ensure_ascii=False)
        fh.write("\n")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Fingerprint y subparticiones reales (DISCOVERY.md seccion 4).")
    parser.add_argument("--cluster", required=True, help="nombre del cluster")
    parser.add_argument("--raw-dir", default=None,
                        help="directorio de JSON por nodo (por defecto DISCOVERY_RAW "
                             "o <repo>/data/raw/discovery/<cluster>)")
    parser.add_argument("--out-dir", default=None,
                        help="si se indica, escribe subpartitions.json y nodelists")
    parser.add_argument("--include-login", action="store_true",
                        help="incluye el nodo de login como nodo mas")
    args = parser.parse_args(argv)

    raw_dir = args.raw_dir or os.environ.get("DISCOVERY_RAW") or os.path.join(
        REPO_ROOT, "data", "raw", "discovery", args.cluster)
    if not os.path.isdir(raw_dir):
        sys.stderr.write("fingerprint: no existe %s\n" % raw_dir)
        return 1

    nodes = load_nodes(raw_dir, args.include_login)
    if not nodes:
        sys.stderr.write("fingerprint: no hay JSON de nodo en %s\n" % raw_dir)
        return 1

    report = build(nodes)
    if args.out_dir:
        write_outputs(report, args.out_dir)
        sys.stderr.write("fingerprint: %d subparticiones en %s\n"
                         % (len(report["subpartitions"]), args.out_dir))
    else:
        json.dump(report, sys.stdout, indent=2, ensure_ascii=False)
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
