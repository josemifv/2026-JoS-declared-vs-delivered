#!/usr/bin/env python3
"""Cargador del reetiquetado de fase B (DEVIATIONS 2026-10-05, [D] auditoría).

Las celdas «1n/2n/4n» de 83314-83318 y 83405-83407 no corrieron con 64 ranks/nodo:
corrieron con 64/128/256 ranks repartidos en 8 nodos. Este módulo aplica el
fichero versionado `relabel-faseB-2026-10-05.csv` (job, celda, etiqueta original,
etiqueta corregida, motivo) a las filas de análisis:

    from relabel import aplica
    runs = aplica(runs)          # añade 'celda_label' corregida y 'repetir'
    # y excluye del veredicto de la hipótesis 3, fichas y validación E-f:
    runs_h3 = [r for r in runs if not r["reetiquetada"]]

Las celdas 8n de los mismos jobs son válidas y no aparecen en el fichero.
"""
from __future__ import annotations

import csv
from pathlib import Path

FICHEROS = sorted(Path(__file__).resolve().parent.glob("relabel-*.csv"))


def cargar() -> dict[tuple[str, str], dict]:
    m = {}
    for fichero in FICHEROS:
        with open(fichero) as f:
            for r in csv.DictReader(f):
                m[(r["job"], r["celda"])] = r   # ft8n 83494/83495 (2ª auditoría B8)
    return m


def aplica(runs: list[dict]) -> list[dict]:
    """Añade celda_label/reetiquetada a cada run (job, celda) del fichero."""
    m = cargar()
    for r in runs:
        k = (str(r.get("job")), f"{r.get('celda', r.get('kernel', ''))}")
        if k in m:
            r["celda_label"] = m[k]["etiqueta_corregida"]
            r["reetiquetada"] = True
        else:
            r["celda_label"] = r.get("celda", r.get("kernel", ""))
            r["reetiquetada"] = False
    return runs


if __name__ == "__main__":
    m = cargar()
    print(f"{len(m)} celdas reetiquetadas ({', '.join(f.name for f in FICHEROS)})")
