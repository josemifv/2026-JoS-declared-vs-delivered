#!/usr/bin/env python3
"""T36: cronología de usuario, sin escribir datos ni consultar el clúster.

NPB: manifiesto y cmdlog por orden/kernel/pila/ranks, métrica del output por hash.
Los run.log se usan para nodos, no para métricas históricas sobrescritas.
Sin manifiesto, el transporte se etiqueta como observado (o desconocido).
Inicio = primera captura cmdlog UTC, no Start de Slurm. Ronda 1 separada.
"""
import argparse
import csv
import json
import re
import statistics
from collections import defaultdict, deque
from pathlib import Path

NODE = re.compile(r"\bb9p\d{2}\b")
NPB = re.compile(r"/npb/(gcc|intelc|intel)/(spr|sapphirerapids)/(ep|ft|cg|mg)\.([BCD])\.x")
HPCG = re.compile(r"/phaseB/hpcg/(gcc|intelc|intel)/xhpcg")
OSU = re.compile(r"/osu/(?:(gcc|intel)/)?(?:(spr|clx)/)?(?:libexec/.*?/mpi/)?(?:collective|pt2pt)/(osu_\w+)")
TIME = re.compile(r"Time in seconds\s*=\s*([0-9.]+)")


def read(path):
    return path.read_text(errors="replace") if path.is_file() else ""


def ranks(cmd):
    for flag in ("-np", "-n", "--ntasks"):
        if flag in cmd:
            value = cmd[cmd.index(flag) + 1]
            if value.isdigit():
                return int(value)
    for arg in cmd:
        if arg.startswith("--ntasks="):
            return int(arg.split("=", 1)[1])
    return 0


def transport(text):
    fi = re.findall(r"libfabric provider[:= ]+([a-z_;]+)", text)
    ucx = re.findall(r"tag\((rc|dc|ud|tcp)(?:_mlx5|[/_])", text)
    values = sorted(set(fi + ucx))
    return "+".join(values) if values else "no-observable"


def output_path(j, directory, raw):
    # El destino de L10 difiere de /cc/raw/phaseB en el cmdlog.
    name = Path(j.get("out_path") or f"{j.get('out_hash', '')}.out").name
    local = directory / "outputs" / name
    if local.is_file():
        return local
    original = j.get("out_path", "")
    if "/cc/raw/" in original:
        rest = original.split("/cc/raw/", 1)[1]
        if rest.startswith("equivalence/"):
            rest = rest.replace("equivalence/", "equivalence/turgalium/", 1)
        return raw / rest
    return local


def manifest_index(directory):
    """Colas por identidad NPB; transporte y ronda nunca se deducen del nombre."""
    index = defaultdict(deque)
    path = directory / "manifest.csv"
    if path.is_file():
        for f in csv.DictReader(path.open()):
            if f.get("verificacion", "").startswith("SALTADA"):
                continue
            cell = f.get("celda", "ft" if directory.name.startswith("ft8n-") else "")
            kernel = cell.split("-")[0]
            par = f.get("par", "")
            if kernel in ("ep", "ft", "cg", "mg", "hpcg") and par:
                index[(kernel, par.split("/")[0], int(f["ranks"]))].append(f)
    return index


def slurm_index(raw):
    """Solo stdout de jobs nombrados, no todos los outputs por hash."""
    index = defaultdict(list)
    for p in sorted(raw.rglob("*.out")):
        if p.parent.name == "outputs":
            continue
        match = re.search(r"-(\d{5,})(?:[^0-9]|$)", p.name)
        if match:
            index[match.group(1)].append(p)
    return index


def med(values):
    return f"{statistics.median(values):.3f}[n={len(values)}]" if values else "-"


def chronology(repo):
    raw = repo / "data/raw"
    stdout = slurm_index(raw)
    groups = defaultdict(list)
    jobs = {}
    warnings = []
    seen = set()
    inventory = defaultdict(int)
    for cj in sorted(raw.rglob("commands.jsonl")):
        if cj.relative_to(raw).parts[0] == "discovery":
            # Estos run_id incluyen PID de la captura, no JobID de Slurm.
            inventory["discovery"] += 1
            continue
        directory = cj.parent
        entries = []
        for lineno, line in enumerate(cj.read_text().splitlines(), 1):
            try:
                entries.append(json.loads(line))
            except ValueError:
                warnings.append(f"JSON inválido {cj.relative_to(repo)}:{lineno}")
        if not entries:
            continue
        match = re.search(r"(\d{5,})$", directory.name)
        if not match:
            match = re.search(r"(\d{5,})$", str(entries[0].get("run_id", "")))
        if not match:
            continue
        job = match.group(1)
        index = manifest_index(directory)
        runlogs = sorted(directory.rglob("run.log"))
        node_sources = {}
        for p in runlogs:
            ns = set(NODE.findall(read(p)))
            if ns:
                node_sources[str(p.relative_to(repo))] = ns
        for p in stdout[job]:
            text = read(p)
            # Solo encabezados de asignación/map-check; no argumentos --exclude.
            ns = set()
            for line in text.splitlines():
                if ("rank=" in line or "== nodo " in line
                        or re.fullmatch(r"(?:b9p\d{2}\s*)+", line.strip())):
                    ns.update(NODE.findall(line))
            if ns:
                node_sources[str(p.relative_to(repo))] = ns
        union = set().union(*node_sources.values()) if node_sources else set()
        info = jobs.setdefault(job, {"nodes": set(), "sources": set(), "start": "", "dirs": set()})
        info["nodes"].update(union)
        info["sources"].update(node_sources)
        info["dirs"].add(str(directory.relative_to(repo)))
        start = min(j.get("ts", "") for j in entries if j.get("ts")) if any(j.get("ts") for j in entries) else ""
        info["start"] = min(filter(None, (info["start"], start)), default="")
        inventory[str(cj.relative_to(raw)).split("/")[0]] += 1
        for j in sorted(entries, key=lambda x: x.get("ts", "")):
            cmd = j.get("cmd", [])
            command = " ".join(cmd)
            # hostname de cmdlog y salidas de hostname: observaciones reales,
            # no las listas de nodos solicitadas en argumentos.
            info["nodes"].update(NODE.findall(j.get("host", "")))
            if NODE.search(j.get("host", "")):
                info["sources"].add(str(cj.relative_to(repo)))
            if any(Path(arg).name == "hostname" for arg in cmd):
                p = output_path(j, directory, raw)
                ns = set(NODE.findall(read(p)))
                info["nodes"].update(ns)
                if ns:
                    info["sources"].add(str(p.relative_to(repo)))
            npb, osu = NPB.search(command), OSU.search(command)
            hpcg = HPCG.search(command)
            if not npb and not osu and not hpcg:
                continue
            if osu and osu.group(2) == "clx":
                continue
            identity = (job, j.get("ts"), tuple(cmd), j.get("out_hash"))
            out = output_path(j, directory, raw)
            text = read(out)
            nr = ranks(cmd)
            nodes = set(NODE.findall(text))
            info["nodes"].update(nodes)
            if nodes:
                info["sources"].add(str(out.relative_to(repo)))
            pila = (npb or osu or hpcg).group(1) or "desconocida"
            kernel = npb.group(3) if npb else (osu.group(3) if osu else "hpcg")
            queue = index.get((kernel, pila, nr))
            f = queue.popleft() if (npb or hpcg) and queue else None
            if identity in seen:
                continue
            seen.add(identity)
            if index and npb and f is None:
                warnings.append(f"{job}: {kernel}/{pila}/{nr} sin fila de manifiesto ({cj.relative_to(repo)})")
            control = osu and kernel == "osu_allreduce" and "-m" in cmd and cmd[cmd.index("-m") + 1] == "65536"
            par = f["par"] if f else f"{pila}/{transport(text)}(observado)"
            if control:
                par = f"{pila}/default(control)"
            valid = j.get("exit_code") == 0 and bool(text)
            if npb:
                valid = valid and bool(re.search(r"Verification\s*=\s*SUCCESSFUL\b", text))
                if f:
                    valid = valid and f.get("verificacion") == "SUCCESSFUL"
            m = TIME.search(text) if npb else None
            latency = re.search(r"^\s*65536\s+([0-9.eE+-]+)", text, re.M) if osu else None
            groups[(job, par)].append({
                "kernel": kernel, "ranks": nr, "class": npb.group(4) if npb else "",
                "round": f.get("ronda") if f else None, "valid": valid,
                "time": float(m.group(1)) if m else None,
                "osu": float(latency.group(1)) if latency else None,
                "control": bool(control), "ts": j.get("ts", ""),
                "source": str(out.relative_to(repo)), "cmdlog": str(cj.relative_to(repo)),
            })
        for key, queue in index.items():
            if queue:
                warnings.append(f"{job}: {len(queue)} filas sin comando {key}")
                for f in queue:
                    groups[(job, f["par"])].append({
                        "kernel": key[0], "ranks": key[2], "class": "",
                        "round": f.get("ronda"), "valid": False,
                        "time": None, "osu": None, "control": False, "ts": "",
                        "source": str((directory / "manifest.csv").relative_to(repo)),
                        "cmdlog": str(cj.relative_to(repo)),
                    })
    # Conservar asignaciones observadas aunque no tengan NPB/OSU reconocido.
    covered = {job for job, _ in groups}
    for job, info in jobs.items():
        if job not in covered and (len(info["nodes"]) == 8 or "b9p07" in info["nodes"]):
            groups[(job, "sin-par-recuperable")].append({
                "kernel": "-", "ranks": 0, "class": "", "round": None,
                "valid": True, "time": None, "osu": None, "control": False,
                "ts": info["start"], "source": "-", "cmdlog": ",".join(sorted(info["dirs"])),
            })

    print("# inicio_cmdlog UTC (no Start de Slurm); métricas NPB clase D/512 ranks, ronda 1 separada")
    print("# no se compara OSU de otra pila/tamaño con FT Intel; '-' = no disponible; sin ronda = sin separar")
    print("# pares HPCG conservados sin calcular su rendimiento; fallos = salida ausente/exit/NPB no verificado")
    print("# cmdlog inspeccionados: " + ", ".join(f"{k}={v}" for k, v in sorted(inventory.items())))
    print("inicio | job | par | b9p07 | b9p14 | b9p06 | nodos | FT_s | CG_s | MG_s | r1_s | OSU64KiB | fallos | fuente")
    observations = []
    supplemental = []
    for (job, par), runs in sorted(groups.items(), key=lambda item: (jobs[item[0][0]]["start"], item[0])):
        info = jobs[job]
        ns = sorted(info["nodes"])
        eight = len(ns) == 8
        has07 = "b9p07" in ns
        if not ns:
            # No se omite una candidata de 512 ranks cuando faltan nodos observables.
            eight = any(r["ranks"] == 512 for r in runs)
        if not eight and not has07:
            continue
        values = {}
        warm = []
        for kernel in ("ft", "cg", "mg"):
            good = [r for r in runs if r["kernel"] == kernel and r["valid"]
                    and r["class"] == "D" and r["ranks"] == 512 and r["time"] is not None]
            values[kernel] = med([r["time"] for r in good if r["round"] not in (None, "1")])
            unsplit = [r["time"] for r in good if r["round"] is None]
            if unsplit:
                values[kernel] = med(unsplit) + "(sin-ronda)"
            w = [r["time"] for r in good if r["round"] == "1"]
            if w:
                warm.append(f"{kernel}={med(w)}")
        osu_parts = []
        for kernel in sorted({r["kernel"] for r in runs if r["osu"] is not None}):
            measured = [r for r in runs if r["kernel"] == kernel and r["valid"] and r["osu"] is not None]
            if measured:
                unit = "MB/s" if kernel in ("osu_bw", "osu_bibw") else "us"
                part = f"{kernel}={med([r['osu'] for r in measured])}{unit}"
                if all(r["control"] for r in measured):
                    part += f"(primero={measured[0]['osu']},último={measured[-1]['osu']})"
                else:
                    part += "(sin-ronda)"
                osu_parts.append(part)
        osu_summary = ";".join(osu_parts) or "-"
        label = lambda node: "sí" if node in ns else ("no" if len(ns) == 8 else "?")
        sources = sorted({r["cmdlog"] for r in runs})
        row = (f"{info['start'] or '?'} | {job} | {par} | {label('b9p07')} | {label('b9p14')} | "
               f"{label('b9p06')} | {','.join(ns) or '?'} | {values['ft']} | {values['cg']} | "
               f"{values['mg']} | {';'.join(warm) or '-'} | {osu_summary} | "
               f"{sum(not r['valid'] for r in runs)} | {','.join(sources)}")
        if eight:
            print(row)
            # Es evidencia de presencia/ausencia, no una prueba causal por sí sola.
            if len(ns) == 8 and info["start"]:
                day = info["start"][:10]
                if (has07 and day >= "2026-10-09") or (not has07 and day < "2026-10-08"):
                    observations.append((job, par, info["start"], ns, values, warm, osu_summary))
        else:
            supplemental.append(row + f" | NO-8n; ranks={sorted({r['ranks'] for r in runs})}")
            if has07 and info["start"][:10] >= "2026-10-09":
                observations.append((job, par, info["start"], ns, values, warm, osu_summary))
        node_sources = sorted(info["sources"], key=lambda p: (not p.endswith(".out"), len(p), p))
        print(f"# nodos {job}: ejemplo={node_sources[0] if node_sources else '?'}; fuentes={len(node_sources)}")
        samples = {}
        for r in runs:
            if r["time"] is not None or r["osu"] is not None:
                samples.setdefault(r["kernel"], r["source"])
        print(f"# métricas {job}/{par}: " + ";".join(f"{k}={v}" for k, v in sorted(samples.items()))
              + "; todas las salidas se reconstruyen desde el cmdlog citado")
    print("\nOTRAS CAMPAÑAS/TAMAÑOS CON b9p07 (no equivalentes a FT-8n Intel)")
    print("\n".join(supplemental) or "ninguna")
    print("\nADVERTENCIAS")
    relevant = {job for job, info in jobs.items() if "b9p07" in info["nodes"] or len(info["nodes"]) == 8}
    print("\n".join(sorted({w for w in warnings if w.split(":")[0] in relevant or w.startswith("JSON")})) or "ninguna")
    print("\nOBSERVACIONES QUE SEPARAN PRESENCIA DEL NODO Y FECHA (no causalidad)")
    for job, par, ts, ns, values, warm, osuval in observations:
        print(f"{job} {par} {ts} nodos={','.join(ns)} FT={values['ft']} CG={values['cg']} "
              f"MG={values['mg']} r1={';'.join(warm) or '-'} OSU64KiB={osuval}; "
              "solo comparable con misma carga/pila/talla")
    if not observations:
        print("ninguna")
    print("OSU/gcc o un humo aislado no resuelve la lentitud FT/CG de intel/mlx. "
          "La alternancia A-C-A-C contemporánea es necesaria si no hay contraste equivalente.")


def discovery(repo):
    files = sorted((repo / "data/raw/discovery/turgalium").glob("b9p*.json"))
    records = {p.stem: json.loads(p.read_text()) for p in files}
    base = records["b9p07"]
    print("# Descubrimiento histórico de usuario, no estado actual")
    for node, j in records.items():
        print(f"{node}: captura={j['collected_at']} fuente=data/raw/discovery/turgalium/{node}.json")
    keys = sorted(set(base["fingerprint_values"]) | {"server_model", "modules_avail", "lustre_version"})
    for key in keys:
        def value(j):
            real = j.get("attributes", {}).get(key, {}).get("real", {})
            if real.get("observable"):
                return json.dumps(real.get("value"), ensure_ascii=False, sort_keys=True)
            return "NO-OBSERVABLE:" + real.get("reason", "sin dato")
        ref = value(base)
        same = [n for n, j in records.items() if n != "b9p07" and value(j) == ref]
        different = [f"{n}={value(j)}" for n, j in records.items() if n != "b9p07" and value(j) != ref]
        print(f"{key}: b9p07={ref}; iguales={','.join(same) or '-'}; distintos={';'.join(different) or '-'}")
    print("Valores no observables compartidos NO prueban igualdad. No se leen logs del sistema "
          "ni se ejecuta ibstat; se comparan los atributos ya capturados en JSON.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", type=Path)
    parser.add_argument("--descubrimiento", action="store_true")
    args = parser.parse_args()
    repo = args.repo.resolve()
    (discovery if args.descubrimiento else chronology)(repo)


if __name__ == "__main__":
    main()
