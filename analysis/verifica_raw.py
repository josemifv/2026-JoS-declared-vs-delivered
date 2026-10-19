#!/usr/bin/env python3
"""Verificación de integridad de data/raw contra los cmdlog (regla 7g del QA).

Para cada commands.jsonl bajo data/raw/ comprueba, por entrada:
  1. que out_path existe,
  2. que sha256(out_path) == out_hash (el nombre del fichero ES su hash),
  3. que basename(out_path) == out_hash.

Uso:  python3 analysis/verifica_raw.py [raiz]
      (raiz por defecto: data/raw del repositorio)
Salida: resumen por directorio y veredicto global (exit 0 si todo cuadra).
"""
import hashlib
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "data" / "raw")


def _local(p: Path) -> Path:
    """Las rutas del cmdlog son absolutas del clúster (…/cc/raw/… y
    …/scratch/discovery/<part>/…): se reasignan al espejo local (data/raw/…).
    Si ya es local, se queda."""
    s = str(p)
    if "/cc/raw/" in s:
        rest = s.split("/cc/raw/", 1)[1]
        if rest.startswith("equivalence/"):
            rest = "equivalence/turgalium/" + rest.split("equivalence/", 1)[1]
        return ROOT / rest
    if "/scratch/discovery/" in s:
        return ROOT / "discovery" / "turgalium" / s.split("/scratch/discovery/", 1)[1]
    if "/scratch/probe_level1/" in s:
        return ROOT / "probe_level1" / s.split("/scratch/probe_level1/", 1)[1]
    return p if p.exists() else ROOT / p.name


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    if not ROOT.is_dir():
        print(f"!! no existe {ROOT}")
        return 2
    n_cmd = n_out = 0
    fallos = []
    for cj in sorted(ROOT.rglob("commands.jsonl")):
        dir_ok = dir_bad = 0
        for line in open(cj, errors="ignore"):
            try:
                j = __import__("json").loads(line)
            except Exception:
                continue
            n_cmd += 1
            op, oh = j.get("out_path"), j.get("out_hash")
            if not oh:
                continue  # comando sin salida capturada
            p = _local(Path(op)) if op else ROOT / "outputs" / f"{oh}.out"
            if not p.exists() and op:
                # v2 (persona, 2026-10-10, orden informes/ordenes/2026-10-10-T09-verifica.md): datos
                # sincronizados en un destino distinto del de su ruta en el clúster (p. ej.
                # data/raw/b9p07/<A|B>/ para jobs que escriben en phaseB/): la salida está en
                # outputs/ junto a su commands.jsonl.
                alt = cj.parent / "outputs" / Path(op).name
                if alt.exists():
                    p = alt
            if not p.exists():
                fallos.append((cj, "FALTA", op or f"outputs/{oh}.out"))
                continue
            n_out += 1
            if sha256(p) != oh or p.stem != oh:
                fallos.append((cj, "HASH", p.name))
            else:
                dir_ok += 1
        if dir_ok or dir_bad:
            pass  # detalle por dir solo si se pide; el resumen es global
    print(f"comandos en cmdlog: {n_cmd}; salidas verificadas: {n_out}; fallos: {len(fallos)}")
    for cj, tipo, nombre in fallos[:50]:
        print(f"  {tipo}  {nombre}  ({cj})")
    if len(fallos) > 50:
        print(f"  ... y {len(fallos) - 50} más")
    return 0 if not fallos else 1


if __name__ == "__main__":
    sys.exit(main())
