# Invocaciones canónicas de análisis

Las invocaciones exactas con las que se generan los derivados de `data/derived/`.
Cualquier regeneración debe producir salidas idénticas (verificación: byte a byte).
## Equivalencia Turgalium — grupos completos (T45)

Desde la raíz del repositorio, con Python ≥ 3.9 y biblioteca estándar:

```sh
python3 -B - <<'PY'
import json
from pathlib import Path
nb = json.loads(Path('analysis/analisis.ipynb').read_text())
ns = {}
for i in (1, 2, 3, 4):
    exec(compile(''.join(nb['cells'][i]['source']), f'analisis.ipynb:celda-{i}', 'exec'), ns)
PY
```

Ejecuta solo las celdas de equivalencia y grupos; no ejecuta la deduplicación de
discovery ni la celda de switches. Los fingerprints se calculan en memoria con
`discovery/fingerprint.py`, sin escribir derivados de descubrimiento. `-B`
evita crear cachés de Python.

- Entrada: todos los `*/commands.jsonl` de `data/raw/equivalence/turgalium/`,
  incluidas las ampliaciones 83703–83716. Ambos hosts del cmdlog identifican el
  par; solo la salida con resultados OSU aporta muestras. Se comprueba su
  SHA256 y `exit_code=0`, se descarta el calentamiento por job/celda y se
  acumulan las muestras efectivas de todos los jobs, sin sobrescribir ni
  deduplicar por hash.
- Salida: `data/derived/equivalence/turgalium/grupos_ejecucion.json`,
  `nodelist_<particion>_<grupo>.txt`, `exclusion_<particion>.txt` (métrica y
  diferencia porcentual) y `no_probados_<particion>.txt` (métricas ausentes).
  El JSON incluye `no_probados` en las particiones CPU.
  Si desaparece un grupo, se retira únicamente su nodelist derivado obsoleto.
- R1, comparación con la referencia, leave-one-out, selección intra-switch
  por el prefijo observado y partición SMT se conservan. Una comparación sin
  referencia suficiente aborta: no se inventa una atribución.
- Los nodos CPU necesitan las tres métricas válidas. Volta/h100 conservan el
  caso degenerado de grupos singleton y OSU omitido declarado, no grupos
  multinodo; no se les exige una medida OSU omitida por diseño.

Para verificar sin modificar los derivados versionados, ejecutar el mismo
bloque con `CC_EQ_OUT` apuntando a un directorio temporal externo. C1 lo
ejecuta dos veces así y compara todos los ficheros byte a byte, normalizando
únicamente el valor de `generated_at` del JSON.

La referencia anterior de C3 se reconstruyó con el notebook original y se
versionó antes del cambio. Reproduce la copia local generada el 2026-10-05,
salvo `generated_at`; no es un derivado recuperado del historial, donde no
existía. Su procedencia y los cambios por partición constan en las notas T45.

## Ligero cpu36c — R2 con 7 pares (2026-10-05)

Verificada: reproduce **byte a byte** `data/derived/ligero-cpu36c/`
(r2.json, celdas.csv, runs.csv, control_db.csv) con los datos de `data/raw/ligero/`
(incluidos los `cc-lig36-*.out` de cada asignación, que dan las marcas de ronda).

```
python3 analysis/fase_a.py --raw data/raw/ligero --out data/derived/ligero-cpu36c \
  --pt2pt-jobs osu36-pt2pt-83381,osu36-pt2pt-83382,osu36-pt2pt-83422,osu36-pt2pt-83423 \
  --coll-jobs osu36-coll-83384,osu36-coll-83385,osu36-coll-83386,osu36-coll-83387,osu36-coll-83425,osu36-coll-83426
```

- Pares intra-switch para la puntuación R2 (los cruzados 83383/83424 quedan fuera
  de la puntuación y se reportan aparte, D2/E-b): 83381 intra SMT-off gcc,
  83382 intra SMT-on gcc, 83422 intra SMT-off verbs, 83423 intra SMT-on verbs.
- R2 por grupo (misma invocación, jobs del grupo):
  - SMT-off: `--pt2pt-jobs osu36-pt2pt-83381,osu36-pt2pt-83422 --coll-jobs osu36-coll-83384,osu36-coll-83385,osu36-coll-83425`
  - SMT-on: `--pt2pt-jobs osu36-pt2pt-83382,osu36-pt2pt-83423 --coll-jobs osu36-coll-83386,osu36-coll-83387,osu36-coll-83426`
- Selección oficial (7 pares): **gcc/rc, intel/mlx, gcc/dc, intel/verbs** — igual
  en SMT-off, SMT-on y conjunto (verificado por la persona, 2026-10-05).
- La tabla «6 pares» anterior (2026-10-05) quedó SUSTITUIDA: mezclaba el par
  cruzado (n=30) en la puntuación «solo intra».

## Controles D-B (2026-10-05)

```
python3 analysis/controles_db.py
```

Regenera `data/derived/controles-db.csv` y `controles-db-resumen.csv` desde
`data/raw` (control-*.log de fase B y ligero; fase A desde commands.jsonl +
outputs por hash).

## Verificación de integridad de data/raw (QA 7g, tras cada job)

```
python3 analysis/verifica_raw.py
```

Comprueba por cada entrada de commands.jsonl que la salida existe y que su
sha256 coincide con `out_hash` (exit 0 = todo cuadra).

## Validación E-f (2026-10-06, material de la persona)

```
python3 analysis/ef_validacion.py . > data/derived/ef/ef_resultado.json
```

Genera `data/derived/ef/ef_resultado.json`: recomendación del ligero,
veredictos de concordancia ligero/matriz por carga (FT, CG, HPCG, MG, EP) a
3/5/10 %. Resultado de la ejecución del 2026-10-06: recomendación del ligero
**gcc/dc**; concordante en FT, CG y HPCG (y MG/EP) con el 5 %; **HPCG NO
concordante con el 3 %**. Informe: `informes/2026-10-06-validacion-ef.md`.

## Reetiquetado de fase B (celdas 1n/2n/4n mal ejecutadas)

`analysis/relabel-faseB-2026-10-05.csv` + cargador `analysis/relabel.py`
(DEVIATIONS 2026-10-05 [D]): el análisis debe aplicar `relabel.aplica(runs)` y
EXCLUIR las filas reetiquetadas (`reetiquetada: True`) del veredicto de la
hipótesis 3, de las fichas de ejecución y de la validación E-f.
