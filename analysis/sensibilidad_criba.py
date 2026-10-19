#!/usr/bin/env python3
"""Sensibilidad de las exclusiones de la criba de Turgalium (respuesta a la revisión de v10d).

Re-ejecuta las celdas 1-4 de analysis/analisis.ipynb (carga, subparticiones, R1 y
leave-one-out) sin modificar el notebook, con dos variaciones:
  - umbral de R1: 3, 5 (registrado) y 10 %;
  - Triad del candidato como sus repeticiones efectivas (se aplica la condición
    de IQR) en lugar de su mediana, con la referencia como repeticiones agrupadas.
Las salidas del notebook se escriben en un directorio temporal (CC_EQ_OUT); no
se escribe nada en el repositorio. Imprime las exclusiones de cpu112c y cpu36c.
Uso: python3 analysis/sensibilidad_criba.py <repo>
"""
import contextlib, io, json, os, sys, tempfile

REPO = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else '.')
nb = json.load(open(os.path.join(REPO, 'analysis/analisis.ipynb')))
SRC = [''.join(nb['cells'][i]['source']) for i in (1, 2, 3, 4)]

def run(thr, triad_raw):
    s = list(SRC)
    s[2] = s[2].replace('<= 0.05', f'<= {thr}')
    if triad_raw:
        rep = [(2, "triadM = [med(triad[n]) for n in triad if n in M]",
                   "triadM = [x for n in triad if n in M for x in triad[n]]"),
               (2, "tC = [med(triad[n]) for n in nodes_m]",
                   "tC = [x for n in nodes_m for x in triad[n]]"),
               (3, "tM = [med(triad[m]) for m in g if m in triad and m != n]",
                   "tM = [x for m in g if m in triad and m != n for x in triad[m]]"),
               (3, "tC = [med(triad[n])] if n in triad else []",
                   "tC = list(triad[n]) if n in triad else []")]
        for k, a, b in rep:
            assert s[k].count(a) == 1, a
            s[k] = s[k].replace(a, b)
    os.environ['CC_EQ_OUT'] = tempfile.mkdtemp()
    os.environ['CC_REPO'] = REPO
    g = {'__name__': 'sensibilidad'}
    with contextlib.redirect_stdout(io.StringIO()):
        for c in s:
            exec(c, g)
    return g['salida']['partitions']

for thr in (0.03, 0.05, 0.10):
    for raw in (False, True):
        sal = run(thr, raw)
        print(f'umbral={int(thr*100)} % triad={"repeticiones" if raw else "mediana"}')
        for p in ('cpu112c', 'cpu36c'):
            ex = []
            for e in sal[p]['exclusion']:
                nodes = ','.join(e.get('nodes') or [e['node']])
                det = ' '.join(f"{k}{e['difference_pct'][k]:+.2f}%" for k, v in e['r1'].items() if v)
                ex.append(f'{nodes} ({det})')
            print(f'  {p}: grupos {[len(x) for x in sal[p]["execution_groups"]]}; excluidos: {"; ".join(ex)}')
