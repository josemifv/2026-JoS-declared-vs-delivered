#!/usr/bin/env python3
"""Adaptación del transporte/pin observado de experiments/ligero112_verif.sbatch.
Origen SHA256: c72705ae107f3c912d1c295b351e27e13f963cf9a76c02a16ece5f00f9ed72ce
Solo emite la fila CSV del probe; no selecciona pares ni cambia el perfil.
"""
import csv
import re
import sys
from pathlib import Path


def fila(pila, pedido, ec, lib_ec, log, libs):
    if pila == "gnu":
        lanes = re.findall(r"(?:inter-node cfg#\d+|ep_cfg\[\d+\]):?\s*tag\(([^)]*)\)", log)
        # «sm» no está en la lista de TASKS.md, pero verif.sbatch pide UCX_TLS="$trans,sm,self":
        # si aparece en la misma configuración que el transporte pedido, hay que descartarlo igual.
        ignored = {"self", "posix", "sysv", "sm", "cma", "knem", "xpmem"}
        effective = []
        for lane in lanes:
            transports = [part.split("/")[0].split(":")[0] for part in re.split(r"[\s,]+", lane.strip()) if part]
            transports = [transport for transport in transports if transport not in ignored]
            if transports:
                effective.append(transports)
        observed = sorted(set(transport for lane in effective for transport in lane))
        match = bool(effective) and all(lane[0] == pedido for lane in effective)
        library = "libmpi.so.40" in libs and "openmpi" in libs.lower()
    else:
        observed = sorted(set(re.findall(r"libfabric provider[:= ]+([a-z0-9_;]+)", log)))
        match = observed == [pedido]
        library = "libmpi.so.12" in libs and ("intel" in libs.lower() or "oneapi" in libs.lower())
    asked = re.findall(r"pin-pedido: host=(\S+) rank=(\d+) core=(\d+)", log)
    actual = re.findall(r"pin-real: host=(\S+) rank=(\d+) cpus=(\S+)", log)
    affinity = (len(asked) == len(actual) == 2 and
                len({h for h, _, _ in actual}) == 2 and
                {r for _, r, _ in actual} == {"0", "1"} and
                sorted(asked) == sorted(actual))
    pin = pila != "intel" or not re.search(r"MPI startup\(\):.*\bPin cpu\b", log)
    valid = int(ec) == 0 and int(lib_ec) == 0 and match and affinity and pin and library
    return [pila, pedido, ec, " ".join(observed) or "sin-observar",
            "si" if match else "no", "si" if affinity and pin else "no",
            "si" if library else "no", "OK" if valid else "FALLO"]


if __name__ == "__main__":
    pila, pedido, ec, lib_ec, log_path, libs_path = sys.argv[1:]
    csv.writer(sys.stdout, lineterminator="\n").writerow(
        fila(pila, pedido, ec, lib_ec, Path(log_path).read_text(errors="replace"),
             Path(libs_path).read_text(errors="replace")))
