#!/usr/bin/env python3
"""Análisis preliminar local de T49. Solo biblioteca estándar; ninguna red.

Lee el worktree indicado sin importar ni ejecutar código del repositorio.
Escribe exclusivamente resultados.csv e informe.md junto a este script.
Uso: python3 -B analiza_xula.py --repo /ruta/al/worktree-carril-c
"""
import argparse
import collections
import csv
import datetime
import hashlib
import json
import math
from pathlib import Path
import re
import statistics


def read(p):
    return p.read_text(encoding='utf-8', errors='replace')


def percentile(a, p):
    a = sorted(a)
    z = (len(a) - 1) * p
    i = math.floor(z)
    return a[i] + (a[min(i + 1, len(a) - 1)] - a[i]) * (z - i)


def summary(a):
    if not a:
        return {}
    q1, q3 = percentile(a, .25), percentile(a, .75)
    return dict(n=len(a), median=statistics.median(a), q1=q1, q3=q3,
                iqr=q3-q1, minimum=min(a), maximum=max(a))


def r1(a, b):
    if not a:
        return dict(r1='sin_muestras_efectivas')
    if not b:
        return dict(r1='sin_referencia_independiente')
    x, y = summary(a), summary(b)
    delta = 100 * abs(x['median']-y['median']) / min(x['median'], y['median'])
    separate = x['q3'] < y['q1'] or y['q3'] < x['q1']
    return dict(r1='distinguible' if delta > 5 and separate else 'no_distinguible',
                difference_pct=delta, signed_change_pct=100*(x['median']/y['median']-1),
                iqrs_disjoint=int(separate), ref_n=y['n'], ref_median=y['median'],
                ref_q1=y['q1'], ref_q3=y['q3'])


def expand_nodes(s):
    out = []
    for prefix, group in re.findall(r'([A-Za-z]+)\[([^]]+)\]', s):
        for part in group.split(','):
            if '-' in part:
                a, b = part.split('-')
                out.extend(prefix + str(i).zfill(len(a)) for i in range(int(a), int(b)+1))
            else:
                out.append(prefix + part)
    return sorted(set(out))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, required=True)
    args = ap.parse_args()
    root = args.repo.resolve()
    out = Path(__file__).resolve().parent
    # El destino no puede redirigirse al worktree de datos.
    if out == root or root in out.parents:
        raise SystemExit('El script debe estar fuera del worktree de datos.')

    def relative(p):
        return str(p.relative_to(root))

    def cite(p, line=None):
        return relative(p) + (':' + str(line) if line else '')

    def matching(p, pattern):
        return [cite(p, i) for i, t in enumerate(read(p).splitlines(), 1)
                if re.search(pattern, t)]

    eq = root / 'data/raw/xula/equivalence'
    disc = root / 'data/raw/xula/fase1/discovery'
    evidence = root / 'informes/tareas/T49'
    docs = {p.stem: json.loads(read(p)) for p in sorted(disc.glob('*.json'))
            if json.loads(read(p)).get('role') == 'node'}
    # Mismo criterio de fingerprint que discovery/fingerprint.py: atributos F
    # observables en todos los nodos, memoria redondeada a bloques de 64 GiB.
    keys = list(dict.fromkeys(k for d in docs.values() for k in d['fingerprint_attrs']))
    used = [k for k in keys if all(d['attributes'].get(k, {}).get('real', {}).get('observable')
            and d['attributes'][k]['real'].get('value') is not None for d in docs.values())]
    groups = collections.defaultdict(list)
    for node, doc in docs.items():
        vals = {k: doc['attributes'][k]['real']['value'] for k in used}
        if 'memory_total_kb' in vals:
            vals['memory_total_kb'] = round(float(vals['memory_total_kb']) / 1048576 / 64) * 64
        key = hashlib.sha256(json.dumps(vals, sort_keys=True, separators=(',', ':'),
                                      ensure_ascii=False).encode()).hexdigest()
        groups[key].append(node)
    ordered = sorted(groups.items(), key=lambda kv: (-len(kv[1]), kv[0]))
    majority = set(ordered[0][1])
    node_group = {n: str(i) for i, (_, ns) in enumerate(ordered) for n in ns}

    partition_file = root / 'informes/tareas/T22/R05.txt'
    parts = read(partition_file).splitlines()
    start = next(i for i, t in enumerate(parts) if 'PartitionName=xula4' in t)
    end = next((i for i in range(start+1, len(parts)) if 'PartitionName=' in parts[i]), len(parts))
    block = '\n'.join(parts[start:end])
    declared = expand_nodes(re.search(r'\bNodes=(\S+)', block)[1])
    declared_source = cite(partition_file, start+1)

    records, jobs, slurm, integrity = [], [], [], []
    for d in sorted(eq.iterdir()):
        mt = re.fullmatch(r'(humo|medida)-(\d+)', d.name)
        if not d.is_dir() or not mt:
            continue
        mode, job = mt[1], int(mt[2])
        if job != 2736189 and not 2736190 <= job <= 2736204 and not 2736912 <= job <= 2736931:
            continue
        campaign = 'L15' if job < 2736912 else 'L15b'
        nodes = read(d/'nodes.txt').split()
        command_rows = [json.loads(t) for t in read(d/'commands.jsonl').splitlines()]
        manifest = d/'manifest.csv'
        rows = list(csv.DictReader(manifest.open()))
        jobs.append(dict(job=job, campaign=campaign, mode=mode, nodes=nodes,
                         rows=len(rows), source=cite(manifest)))
        for node in nodes:
            f = d/('slurm-' + node + '.txt')
            fields = dict(re.findall(r'\b(NodeName|CPUAlloc|CPUTot|CPULoad|State|OverSubscribe|AllocTRES)=(\S+)', read(f)))
            slurm.append(dict(job=job, node=node, source=cite(f, 1), **fields))
        for line, row in enumerate(rows, 2):
            bench, pair, rnd = row['bench'], row['nodes'].split(';'), int(row['ronda'])
            rd = d / (f'stream-{pair[0]}-{rnd}' if bench == 'stream' else f'{bench}-{rnd}')
            f = rd/'run.log'
            text = read(f)
            # Contrastar el log con el hash registrado por la invocación exterior.
            cmds = [(i, c) for i, c in enumerate(command_rows, 1)
                    if any(str(a).endswith('/'+rd.name) for a in c['cmd'])
                    and '_rank' in c['cmd'] and Path(c['cmd'][0]).name in ('srun', 'mpirun')]
            assert len(cmds) == 1, (job, rd.name, len(cmds))
            ci, c = cmds[0]
            assert hashlib.sha256(f.read_bytes()).hexdigest() == c['out_hash'], f
            assert str(c['exit_code']) == row['exit_code'], (job, rd.name)
            integrity.append(cite(d/'commands.jsonl', ci))
            pattern = r'^Triad:\s+([\d.eE+-]+)' if bench == 'stream' else rf'^\s*{8 if bench == "lat" else 4194304}\s+([\d.eE+-]+)\s*$'
            found = [(i, re.search(pattern, t)) for i, t in enumerate(text.splitlines(), 1) if re.search(pattern, t)]
            assert len(found) == 1, (job, rd.name, len(found))
            ln, val = found[0]
            value = float(val[1]) / (1000 if bench == 'stream' else 1)
            assert math.isfinite(value) and value > 0
            size = re.search(r'^Array size = (\d+) \(elements\)', text, re.M)
            if bench == 'stream':
                assert size and int(size[1]) == 40000000, ('tamaño no comparable', f)
            # Evidencia de la selección entre extremos, no componentes cargados.
            observed = set()
            selection_lines = []
            if bench != 'stream':
                for lineno, textline in enumerate(text.splitlines(), 1):
                    m = re.search(r'\[([^:\]]+):\d+\].*?mca: bml: Using (\S+) btl for send to .*? on node (\S+)', textline)
                    if m and m[1].split('.')[0] in pair and m[3].split('.')[0] in pair and m[1].split('.')[0] != m[3].split('.')[0]:
                        observed.add('btl:'+m[2]); selection_lines.append(cite(f,lineno))
            rec = dict(record_type='run', campaign=campaign, job=str(job), mode=mode,
                       node=';'.join(pair), peer='', metric={'stream':'triad','lat':'latency_8B','bw':'bandwidth_4MiB'}[bench],
                       round=rnd, warmup=row['warmup'], exit_code=row['exit_code'], verification=row['verificacion'],
                       eligible=int(row['warmup']=='0' and row['exit_code']=='0' and row['verificacion']=='OK'),
                       value=value, unit={'stream':'GB/s_decimal','lat':'us','bw':'MB/s_decimal'}[bench],
                       stream_elements=int(size[1]) if size else '', transport=row['transporte'],
                       transport_observed=';'.join(sorted(observed)),
                       transport_sources=';'.join(selection_lines),
                       ucx_init_failures=len(re.findall(r'init returned failure for component ucx',text)),
                       source=cite(f, ln), manifest_source=cite(manifest, line),
                       command_source=cite(d/'commands.jsonl', ci), sha256=c['out_hash'])
            records.append(rec)

    def samples(campaign, node, metric, job=None):
        return [r for r in records if r['eligible'] and r['campaign']==campaign and r['metric']==metric
                and node in r['node'].split(';') and (job is None or r['job']==str(job))]

    def pool(campaign, node, metric):
        # STREAM: leave-one-node-out. MPI: excluir el par del candidato,
        # usar solo pares distintos con ambos extremos de la mayoría.
        return [r for r in records if r['eligible'] and r['campaign']==campaign and r['metric']==metric
                and set(r['node'].split(';')) <= majority and node not in r['node'].split(';')]

    summaries = []
    for campaign in ['L15', 'L15b']:
        nodes = sorted({n for j in jobs if j['campaign']==campaign for n in j['nodes']})
        for node in nodes:
            for metric in ['triad', 'latency_8B', 'bandwidth_4MiB']:
                a, ref = samples(campaign,node,metric), pool(campaign,node,metric)
                vals, refs = [r['value'] for r in a], [r['value'] for r in ref]
                s = dict(record_type='node_summary',campaign=campaign,node=node,metric=metric,
                         unit={'triad':'GB/s_decimal','latency_8B':'us','bandwidth_4MiB':'MB/s_decimal'}[metric],
                         majority_group=node_group[node], in_majority=int(node in majority),
                         reference_nodes=';'.join(sorted({n for r in ref for n in r['node'].split(';')})),
                         source=';'.join(r['source'] for r in a), reference_sources=';'.join(r['source'] for r in ref),
                         **summary(vals), **r1(vals,refs))
                summaries.append(s)
    job_summaries = []
    for j in jobs:
        for node in j['nodes']:
            for metric in ['triad','latency_8B','bandwidth_4MiB']:
                rr = samples(j['campaign'],node,metric,j['job'])
                job_summaries.append(dict(record_type='job_summary', campaign=j['campaign'],job=str(j['job']),
                    node=node, metric=metric, source=';'.join(r['source'] for r in rr),
                    **summary([r['value'] for r in rr])))
    diagnostics = []
    for s in summaries:
        rr = [r for r in records if r['campaign']==s['campaign'] and r['metric']==s['metric']
              and s['node'] in r['node'].split(';') and r['warmup']=='0' and r['exit_code']=='0']
        diagnostics.append(dict(record_type='diagnostic_exit0_summary', campaign=s['campaign'],
            node=s['node'],metric=s['metric'],source=';'.join(r['source'] for r in rr),
            verification='incluye_FALLO_sin_rehabilitar',**summary([r['value'] for r in rr])))

    # Contabilidad: una sola fila por job. No sumar las repeticiones de sondeos.
    accounting = {}
    target = {j['job'] for j in jobs} | set(range(2736190,2736205)) | set(range(2736912,2736932))
    for f in sorted(evidence.rglob('*.txt')):
        for line, text in enumerate(read(f).splitlines(),1):
            if not re.match(r'^\d+\|',text):
                continue
            fields=text.split('|')
            if len(fields)!=7 or not fields[0].isdigit() or int(fields[0]) not in target:
                continue
            job=int(fields[0]); state=fields[2]
            if state not in ('COMPLETED','FAILED','TIMEOUT','CANCELLED','NODE_FAIL','OUT_OF_MEMORY'):
                continue
            ts=fields[4]; day=0
            if '-' in ts:
                dd,ts=ts.split('-',1);day=int(dd)
            hh,mm,ss=map(int,ts.split(':'))
            seconds=86400*day+3600*hh+60*mm+ss
            item=dict(record_type='cost',campaign='L15' if job<2736912 else 'L15b',job=str(job),
                      state=state, elapsed_seconds=seconds, nnodes=int(fields[5]),
                      node_hours=seconds*int(fields[5])/3600, source=cite(f,line))
            if job in accounting:
                prev=accounting[job]
                assert (prev['state'],prev['elapsed_seconds'],prev['nnodes'])==(state,seconds,int(fields[5])), job
            else:
                accounting[job]=item

    measured={n for r in records if r['eligible'] and r['metric']=='triad' for n in r['node'].split(';')}
    smoked={n for j in jobs if j['mode']=='humo' for n in j['nodes']}
    missing=sorted(set(declared)-measured)
    coverage=[dict(record_type='coverage',node=n,discovered=int(n in docs),
                   effective_measured=int(n in measured),smoke_only=int(n in smoked and n not in measured),
                   source=declared_source+';'+(cite(disc/(n+'.json')) if n in docs else 'sin_JSON_local'))
              for n in declared]
    allrows=records+summaries+job_summaries+diagnostics+list(accounting.values())+coverage
    columns=list(dict.fromkeys(k for r in allrows for k in r))
    with (out/'resultados.csv').open('w',newline='',encoding='utf-8') as fh:
        writer=csv.DictWriter(fh,fieldnames=columns);writer.writeheader();writer.writerows(allrows)

    def fmt(v,n=3):
        return '—' if v is None or v=='' else f'{v:.{n}f}'

    def cell(s):
        return 'sin efectivas' if not s.get('n') else f"{s['median']:.3f} [{s['q1']:.3f}, {s['q3']:.3f}] (n={s['n']})"

    def code(s):
        return '`'+s+'`'

    def compact_sources(sources):
        """Agrupa solo nombres realmente existentes; llaves = expansión literal."""
        g=collections.defaultdict(list)
        other=[]
        for source in sources:
            m=re.match(r'^(.*(?:/stream-[^-]+-|/(?:lat|bw)-))(\d+)(/run.log:\d+)$', source)
            if m:
                g[(m[1],m[3])].append(int(m[2]))
            else:
                other.append(source)
        return ', '.join(code(prefix+'{'+','.join(map(str,sorted(set(rounds))))+'}'+suffix)
                         for (prefix,suffix),rounds in sorted(g.items())) + (', '+', '.join(map(code,other)) if other else '')

    report=[]
    def add(s=''):
        report.append(s)

    now=datetime.datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S %Z')
    add('# Xula: análisis preliminar local de la prueba de equivalencia')
    add(f'\nGenerado: {now}. Solo lecturas de archivos locales. Sin red ni ejecución de comandos de clúster. Los únicos productos son este informe, resultados.csv y analiza_xula.py en el directorio autorizado.')
    add('\n## Lectura principal')
    add('\n**Se observa selección automática de OB1/TCP, no una elección explícita de TCP en el protocolo.** El componente PML UCX falla al inicializarse en los logs examinados y Open MPI selecciona OB1; la selección TCP queda registrada. Esto es un fallback de la pila GNU bajo sus valores por defecto. No demuestra una avería física de InfiniBand ni identifica su causa. La criba mide el camino TCP realmente utilizado, no el máximo de la red RDMA.')
    add('\n**No todas las caídas STREAM corresponden a un nodo permanentemente lento.** Hay caídas aisladas incluso en el nodo de referencia; xula5304 permanece bajo en todas sus rondas efectivas de una asignación; xula5401 alterna dos regímenes. La persistencia temporal fuera de esas asignaciones no está medida. Las fuentes por ronda y por job se detallan abajo; no se suprime ningún valor bajo.')
    add('\n## Método y límites del cálculo')
    add('\nFuentes primarias: data/raw/xula/equivalence y data/raw/xula/fase1 del worktree indicado. No se leen archivos privados de entorno. Se lee texto de scripts/perfil para documentar el diseño, sin ejecutarlos. Las citas son rutas relativas al worktree de datos, seguidas de línea. Cada fila run del CSV conserva fuente exacta de la cifra, línea del manifiesto, comando, hash, verificación y calentamiento.')
    add('\nSe calcula la mediana y Q1/Q3 por interpolación lineal en posiciones (n−1)p; IQR=Q3−Q1. Se excluye el calentamiento de cada job/celda y, del resumen principal, las filas con exit distinto de cero o verificación distinta de OK. Se conservan en el CSV con eligible=0. No se equipara un fallo del job con un fallo de cada benchmark: muchas celdas anteriores al fallo tienen exit 0 y comprobación OK. Fuente de R1: rules/RULES.md:9–16; se aplica |mediana−referencia|/min(medianas)>0,05 y Q3<Q1 del otro grupo. El denominador menor es el solicitado en este encargo.')
    add('\nLas muestras se agrupan por campaña, nodo y tamaño; no se mezclan campañas para fabricar una referencia estable. La referencia de STREAM reúne muestras efectivas de nodos con fingerprint mayoritario, excluyendo el nodo evaluado. Para MPI, las muestras son del **par**: la referencia reúne otros pares de la mayoría, excluyendo todo par que contenga el nodo evaluado. La medida compartida por dos extremos no se cuenta dos veces en la referencia. Para xula5504 en L15b no existe referencia MPI independiente: todos los pares lo contienen. En L15 solo se midió un par y tampoco hay contraste MPI independiente. R1 es un filtro descriptivo, no una prueba de equivalencia estadística ni una decisión de exclusión aprobada.')
    add('\nLa acumulación por ronda da mayor peso al nodo de referencia repetido en más asignaciones; se muestra también cada job por separado. Las rondas no son réplicas independientes de la partición. Las diferencias de parejas pueden reflejar topología, fecha y extremo compartido; no se atribuyen automáticamente al candidato.')
    add('\n## Transporte: pedido, disponible y utilizado')
    add('\n**Diseño.** experiments/portable/equiv-v2.sbatch:8–11 declara GNU por defecto; :175 carga la pila; :188 activa verbosidad; :270–271 lanza mpirun sin PML/BTL/UCX_TLS forzados. La versión original usa el mismo criterio (equiv.sbatch:279–288). experiments/portable/perfil.sh:59–70 limpia selectores PML/UCX y carga módulos. clusters/perfiles/xula4.env:11 contiene Open MPI y UCX; :19–20 deja transportes POR_DETERMINAR. La orden informes/ordenes/2026-10-14-T49-xula4-equivalencia.md autoriza usar la pila GNU tal como calibra y registrar el transporte, no seleccionar TCP como transporte de referencia.')
    f=eq/'medida-2736914/lat-2/run.log'
    for pat,description in [(r'init returned failure for component ucx','UCX no inicializa'),
                            (r'selected ob1 best priority','Open MPI selecciona OB1'),
                            (r'Using tcp btl for send','BML selecciona TCP entre nodos')]:
        add('\n- '+description+': '+', '.join(code(s) for s in matching(f,pat))+'.')
    add('\nNo se utiliza la presencia de una biblioteca libucp en ldd como prueba de transporte efectivo: el propio log puede cargar UCX y acabar comunicando por OB1/TCP. La verbosidad hace visible el fallback; «silencioso» solo describe que no impide terminar el benchmark, no ausencia de evidencia en estos logs.')
    mpi=[r for r in records if r['metric']!='triad']
    tcp=[r for r in mpi if r['transport_observed']=='btl:tcp']
    add('\nRecuento independiente de las selecciones BML entre extremos en los run.log: '+str(len(tcp))+'/'+str(len(mpi))+' celdas MPI registradas muestran btl:tcp. Fuentes de cada selección: transport_sources del CSV, con fichero y línea, incluyendo calentamientos y filas rechazadas por mapa. No se interpreta el texto transport del manifiesto como única prueba.')
    add('\n**Declaración de red.** En la evidencia local de Slurm no aparece una promesa de RDMA o de modelo/velocidad de red: clusters/xula.md:38 documenta features nulos, topology/none y ausencia de topología; informes/tareas/T22/R04.txt:203–204 y R07.txt:6 son las capturas originales. El nombre del módulo UCX no garantiza que MPI elija UCX o disponga de transportes verbs. No se inventa una especificación pública ausente de estos archivos.')
    x=docs['xula5504']
    for key,title,pattern in [('hca_model','Hardware observado con ibstat',r'CA type:|State:|Physical state:|Rate:|Link layer:'),
                              ('ucx_version','UCX del inventario sin módulos',r'UCT version='),
                              ('ucx_transports','Transportes del UCX del inventario',r'Transport:|Device: ib0')]:
        a=x['attributes'][key]['real'];p=disc/'outputs'/(a['out_hash']+'.out')
        lines=[(i,t.strip()) for i,t in enumerate(read(p).splitlines(),1) if re.search(pattern,t)]
        add('\n'+title+': '+ '; '.join(code(t)+' ('+code(cite(p,i))+')' for i,t in lines)+'.')
    uf=root/'data/raw/xula/fase1/verif-2735894/ucx-info.txt'
    add('\n**UCX bajo el módulo GNU.** '+ '; '.join(code(read(uf).splitlines()[int(s.rsplit(':',1)[1])-1].strip())+' ('+code(s)+')' for s in matching(uf,r'Transport:|Device: ib0'))+'. No hay rc/dc/ud/verbs en esta enumeración; tcp incluye ib0: TCP puede circular por IP sobre InfiniBand. El protocolo TCP no identifica por sí solo el cable o interfaz usados.')
    add('\nVerificación funcional previa: '+code('data/raw/xula/fase1/verif-2735894/manifest.csv:2–5')+' registra fallos para los transportes locales posix/self/sysv entre nodos y éxito de GNU/tcp. Eso refuerza la limitación observada de esta pila; no convierte la prueba de equivalencia en una elección explícita de TCP ni prueba que otras pilas o configuraciones no puedan usar RDMA.')
    add('\n**Interpretación.** Hay una diferencia operativa entre un HCA InfiniBand activo y la comunicación MPI que llega al usuario por defecto. No hay evidencia suficiente para etiquetarla estrictamente como declaración falsa de RDMA por parte de Slurm. Es evidencia de fallback y de transportes RDMA no expuestos por las enumeraciones de UCX disponibles. No se deducen driver, permisos, compilación o avería como causa demostrada.')
    p=disc/'outputs'/(x['attributes']['port_rate']['real']['out_hash']+'.out')
    add('\nEl Rate: 200 de ibstat corresponde a 200 Gb/s de enlace InfiniBand, no a 200 GB/s ni a una medida MPI: '+code(cite(p,11))+'. Las latencias/BW de las tablas son los resultados reales de OSU sobre TCP. La discrepancia entre UCX de sistema y UCX del módulo no es por sí sola un error: son entornos distintos, distinguidos aquí por su fuente.')

    add('\n## Cobertura y configuraciones')
    add(f'\nSlurm declara {len(declared)} nodos: {code(declared_source)} y '+code(cite(partition_file,start+6))+'. Descubrimiento local: '+str(len(docs))+' JSON en data/raw/xula/fase1/discovery; inventario de nombres reproducido en filas coverage del CSV. Fingerprint rehecho con los campos observables comunes y normalización de memoria, tal como discovery/fingerprint.py:69–81,91–159; los hashes guardados originalmente contienen ruido de memoria y no se usan directamente para definir mayoría.')
    for i,(_,nodes) in enumerate(ordered):
        d=docs[nodes[0]]
        add('\n- Grupo '+str(i)+', '+str(len(nodes))+' nodos: '+', '.join(nodes)+'. Fuentes: '+', '.join(code(cite(disc/(n+'.json'))) for n in nodes)+'.')
    add('\nLos grupos se definen dentro del inventario disponible, no de los nodos sin descubrir. Campos reales de topología por grupo, leídos del JSON del representante:')
    add('\n| Grupo / representante | Threads/core | CPUs lógicas | NUMA | BIOS / microcódigo | Fuente |\n|---|---|---|---|---|---|')
    for i,(_,nodes) in enumerate(ordered):
        n=nodes[0];a=docs[n]['attributes'];v=lambda k:a[k]['real']['value']
        add('| '+str(i)+' / '+n+' | '+str(v('threads_per_core'))+' | '+str(v('logical_cpus_online'))+' | '+str(v('numa_nodes'))+' | '+str(v('bios_version'))+' / '+str(v('microcode'))+' | '+code(cite(disc/(n+'.json')))+' |')
    add('\nCobertura con alguna ronda efectiva: '+', '.join(sorted(measured))+'. Solo humo, sin efectivas: '+', '.join(sorted(smoked-measured))+'. Fuentes: '+', '.join(code(j['source']) for j in jobs if j['campaign']=='L15b')+', y '+code('data/raw/xula/equivalence/medida-2736190/manifest.csv')+'. El humo L15b usa una ronda marcada como calentamiento, por lo que xula5003 no tiene estimador de equivalencia válido.')
    add('\n**Faltan rondas efectivas en:** '+', '.join(missing)+'. Sin JSON de descubrimiento local: '+', '.join(sorted(set(declared)-set(docs)))+'. La fuente del universo es '+code(cite(partition_file,start+6))+'; la ausencia se comprueba contra los JSON y manifiestos locales. No se afirma que esos jobs sigan pendientes ahora: solo se describe la última captura disponible.')

    add('\n## Tabla por nodo y campaña: mediana [Q1,Q3]')
    add('\nTriad en GB/s decimales; latencia en µs; ancho de banda OSU en MB/s decimales. Cada celda lleva n efectivo. Las dos métricas MPI pertenecen al par con el compañero indicado, no son medidas unilaterales del nodo. El CSV contiene las fuentes individuales para cada cifra del resumen.')
    add('\n| Campaña / nodo | Compañero(s) | Triad | Latencia 8 B | BW 4 MiB | Fuentes primarias |\n|---|---|---|---|---|---|')
    for campaign in ['L15','L15b']:
        ns=sorted({s['node'] for s in summaries if s['campaign']==campaign})
        for node in ns:
            rows={s['metric']:s for s in summaries if s['campaign']==campaign and s['node']==node}
            js=[j for j in jobs if j['campaign']==campaign and node in j['nodes']]
            peers=sorted({n for j in js for n in j['nodes'] if n!=node})
            sources=', '.join(code(j['source']) for j in js)
            add('| '+campaign+' / '+node+' | '+', '.join(peers)+' | '+' | '.join(cell(rows[k]) for k in ['triad','latency_8B','bandwidth_4MiB'])+' | '+sources+'; run.log de esas celdas, desglosados en CSV |')

    add('\n## R1 frente a la referencia mayoritaria disponible')
    add('\nSe compara únicamente con la fracción medida del grupo mayoritario, no con nodos sin datos. Las filas node_summary de resultados.csv incluyen reference_nodes y reference_sources, además de la mediana/Q1/Q3 de referencia. No se llama «equivalente» a una ausencia de diferencia y no se cambia ninguna lista oficial de ejecución.')
    add('\n| Campaña / nodo / métrica | Mediana [Q1,Q3] de referencia | Diferencia respecto a menor (%) | IQR separados | R1 | Fuentes |\n|---|---|---|---|---|---|')
    for s in summaries:
        ref='—' if 'ref_median' not in s else f"{s['ref_median']:.3f} [{s['ref_q1']:.3f}, {s['ref_q3']:.3f}]"
        js=[j for j in jobs if j['campaign']==s['campaign']]
        origin='data/raw/xula/equivalence/'+('medida-2736190…medida-2736204' if s['campaign']=='L15' else ','.join(('humo-' if j['mode']=='humo' else 'medida-')+str(j['job']) for j in js))
        add('| '+s['campaign']+' / '+s['node']+' / '+s['metric']+' | '+ref+' | '+fmt(s.get('difference_pct'))+' | '+str(s.get('iqrs_disjoint','—'))+' | '+s['r1']+' | '+code(origin)+'; fuentes exactas en node_summary.source/reference_sources |')
    add('\n**Lectura de R1.** xula5304 es distinguible por Triad bajo; xula5201 por Triad alto. El par xula5304–xula5504 es distinguible por BW alto y el par xula5401–xula5504 por latencia menor. Esas diferencias de pares no prueban una anomalía individual del candidato. xula5401 no supera el filtro completo de Triad porque su IQR se solapa, aunque la mediana baje mucho: no debe leerse no_distinguible como ausencia de caídas. Las cifras y fuentes de estos veredictos son las filas correspondientes de la tabla y el índice de fuentes siguiente.')
    add('\n### Índice de fuentes métricas de las tablas por nodo y R1')
    add('\nCada entrada enumera ficheros run.log de origen, con línea exacta de la cifra. Las llaves contienen exclusivamente números de rondas existentes y elegibles: se expanden literalmente a un fichero por número. Las referencias de R1 son subconjuntos de estos mismos ficheros; reference_sources del CSV enumera individualmente el subconjunto exacto de cada fila, sin sintaxis abreviada. Los manifiestos se citan además para justificar inclusiones, n y exclusiones.')
    for s in summaries:
        add('\n- '+s['campaign']+' / '+s['node']+' / '+s['metric']+': '+(compact_sources(s['source'].split(';')) if s['source'] else 'sin cifra efectiva; solo humo o sin celda ejecutada')+'.')

    add('\n## STREAM por job y ronda, sin borrar las caídas')
    add('\nEn la tabla siguiente cada número rN es el Triad de ese run.log; r1 se muestra separado y se descarta del estimador. Una fuente como «stream-NODO-rN/run.log» identifica exactamente el fichero de cada valor sustituyendo N por la ronda de la columna; la fila run del CSV añade su línea exacta. No hay medidas de otro tamaño en esta tabla.')
    add('\n| Job / nodo | Elementos | r1, calentamiento | r2…r11 (GB/s; — si no existe) | Mediana efectiva [Q1,Q3] | Fuente de los valores por ronda |\n|---|---|---|---|---|---|')
    for j in jobs:
        for node in j['nodes']:
            rr=[r for r in records if r['job']==str(j['job']) and r['node']==node and r['metric']=='triad']
            byround={r['round']:r for r in rr}
            ss=summary([r['value'] for r in rr if r['eligible']])
            src=f"data/raw/xula/equivalence/{j['mode']}-{j['job']}/stream-{node}-rN/run.log"
            # El nombre real usa el número, sin el prefijo r: se explica literalmente.
            src=f"data/raw/xula/equivalence/{j['mode']}-{j['job']}/stream-{node}-<N>/run.log"
            add('| '+str(j['job'])+' / '+node+' | '+','.join(str(v) for v in sorted({r['stream_elements'] for r in rr}))+' | '+fmt(byround.get(1,{}).get('value'))+' | '+', '.join('r'+str(i)+'='+fmt(byround.get(i,{}).get('value')) for i in range(2,12))+' | '+cell(ss)+' | '+code(src)+' (N = ronda; Triad:) |')
    add('\n**Tamaño realmente ejecutado.** Todos los run.log STREAM incluidos arriba contienen Array size = 40000000. La compilación del humo lo documenta también en '+code('data/raw/xula/equivalence/humo-2736189/compile/commands.jsonl:2')+'. La orden de 40M corrigió una referencia anterior a una receta de 10M: '+code('informes/ordenes/2026-10-14-T49-stream-40M.md')+'. Los archivos negative-from-real.log con 10M son casos negativos fabricados por el validador, no medidas; experiments/portable/equiv-v2.sbatch:68–74 lo explica. En data/raw/xula/fase1 no se encontró ningún run.log de STREAM con otra dimensión. No se mezcla tamaño por el nombre del binario ni por el texto de la receta antigua.')
    for node in sorted(measured):
        for campaign in ['L15','L15b']:
            rr=samples(campaign,node,'triad')
            if not rr:
                continue
            low=[r for r in rr if r['value']<150]
            # 150 GB/s solo describe el régimen visible; no es una regla de exclusión.
            add('\n- '+campaign+' / '+node+': '+str(len(low))+'/'+str(len(rr))+' rondas efectivas por debajo de 150 GB/s (umbral descriptivo para localizar el régimen bajo, no regla R1). Rango '+fmt(min(r['value'] for r in rr))+'–'+fmt(max(r['value'] for r in rr))+' GB/s. Fuentes del conteo: '+', '.join(code(r['source']) for r in low)+ ('; resto de rondas en la fila anterior/CSV.' if low else 'ninguna ronda baja; todos los run.log de las filas de este nodo en la tabla anterior.') )
    add('\n**Interpretación limitada.** xula5304 es consistentemente bajo dentro del único job efectivo disponible; su r1 alto descarta que todas sus ejecuciones observadas sean siempre lentas. xula5401 es bimodal en ese job, por lo que una mediana intermedia no describe un régimen típico. Las caídas en xula5504 y xula5601, y algunas en otros nodos, son intermitentes. No se puede afirmar defecto persistente del hardware ni una causa común a todos los episodios. El primer job de xula5003 es solo humo y su resultado se conserva sin forzar una mediana efectiva.')

    add('\n## ¿Nodos compartidos con otros usuarios?')
    add('\nLa declaración de la partición xula4 es OverSubscribe=NO: '+code(cite(partition_file,start+7))+'. Los dos scripts de equivalencia declaran #SBATCH --exclusive (equiv.sbatch:11; equiv-v2.sbatch:14). Cada captura slurm-<nodo>.txt examinada da CPUAlloc=112, CPUTot=112 y State=ALLOCATED; no contiene OverSubscribe ni una lista de JobId/usuarios. CPUAlloc lleno no demuestra por sí solo ausencia de procesos ajenos; combinado con --exclusive y OverSubscribe=NO no respalda la hipótesis de compartir cores con otros jobs Slurm. Tampoco demuestra ausencia de demonios, procesos residuales o contención externa. No se infiere ninguno de ellos como causa.')
    add('\n| Job / nodo | CPUAlloc / CPUTot | CPULoad | Estado | Fuente |\n|---|---|---|---|---|')
    for s in slurm:
        add('| '+str(s['job'])+' / '+s['node']+' | '+s.get('CPUAlloc','?')+' / '+s.get('CPUTot','?')+' | '+s.get('CPULoad','?')+' | '+s.get('State','?')+' | '+code(s['source'])+' |')
    add('\nCPULoad es una instantánea previa al bloque STREAM, no una serie sincronizada con cada caída. Sus valores altos en algunos nodos no demuestran por sí solos un job ajeno; los nodos con peores rondas no tienen necesariamente CPULoad alto. La tabla permite comprobarlo sin atribución causal.')

    add('\n## Ejecuciones parciales, validación e integridad')
    add('\n| Job | Filas conservadas | Filas OK / FALLO | Tamaño STREAM | Fuente |\n|---|---|---|---|---|')
    for j in jobs:
        rr=[r for r in records if r['job']==str(j['job'])]
        counts=collections.Counter(r['verification'] for r in rr)
        sizes=sorted({r['stream_elements'] for r in rr if r['metric']=='triad'})
        add('| '+str(j['job'])+' | '+str(len(rr))+' | '+str(counts['OK'])+' / '+str(counts['FALLO'])+' | '+','.join(map(str,sizes))+' | '+code(j['source'])+' |')
    bad=[r for r in records if r['verification']!='OK']
    add('\nLos rechazos del mapa de L15 se conservan, con exit del comando 0: '+', '.join(code(r['manifest_source']) for r in bad)+'. Ejemplo '+code('data/raw/xula/equivalence/medida-2736190/lat-5/check.txt:3')+': host/ranks/mapa. El diagnóstico de intercalación y la corrección figuran en '+code('informes/ordenes/2026-10-15-T49-L15b.md')+'. No se rehabilitan esos runs automáticamente. Sus valores siguen en filas run del CSV, fuera del resumen principal; las celdas nunca ejecutadas siguen ausentes.')
    add('\nResumen diagnóstico adicional de las salidas con exit=0, incluyendo las rechazadas por mapa: no es una rehabilitación ni se aplica a R1. Fuentes: los run.log del índice anterior más las filas FALLO citadas arriba; el CSV diagnostic_exit0_summary enumera exactamente cada fichero añadido.')
    add('\n| Nodo L15 / métrica MPI | n estricto / n diagnóstico | Mediana [Q1,Q3] diagnóstico |\n|---|---|---|')
    for d in diagnostics:
        if d['campaign']=='L15' and d['metric']!='triad':
            s=next(s for s in summaries if (s['campaign'],s['node'],s['metric'])==(d['campaign'],d['node'],d['metric']))
            add('| '+d['node']+' / '+d['metric']+' | '+str(s.get('n',0))+' / '+str(d.get('n',0))+' | '+cell(d)+' |')
    add('\nComprobación independiente local: '+str(len(integrity))+' run.log de manifiestos emparejados con una única invocación exterior de commands.jsonl, hash SHA256 coincidente y mismo exit. Fuentes: campos command_source/sha256 del CSV, que remiten a cada línea cruda. No equivale a revalidar todo el árbol ni a repetir la auditoría remota. La carpeta medida-2.73619e+06 carece de manifiesto; no se inventa un job numérico ni se usa como medida adicional.')

    add('\n## Coste según sacct registrado: jobs terminales, sin duplicar sondeos')
    add('\nSe incluye consumo de COMPLETED y FAILED; una cancelación sin tiempo consumiría cero. No se suman límites de tiempo solicitados ni filas repetidas de vigilancia. Los pendientes no tienen coste consumido conocido. Se cuentan solo jobs de equivalencia T49, no calibración/descubrimiento de fase 1 ni jobs de Lusitania que aparecen en capturas conjuntas.')
    add('\n| Campaña / job | Estado | Nodos | Segundos | Nodo-hora | Fuente sacct exacta |\n|---|---|---|---|---|---|')
    for job,c in sorted(accounting.items()):
        add('| '+c['campaign']+' / '+str(job)+' | '+c['state']+' | '+str(c['nnodes'])+' | '+str(c['elapsed_seconds'])+' | '+fmt(c['node_hours'],6)+' | '+code(c['source'])+' |')
    for campaign in ['L15','L15b']:
        cc=[c for c in accounting.values() if c['campaign']==campaign]
        add('\n- '+campaign+': '+str(len(cc))+' jobs terminales, '+fmt(sum(c['node_hours'] for c in cc),6)+' nodo-h; COMPLETED '+fmt(sum(c['node_hours'] for c in cc if c['state']=='COMPLETED'),6)+', FAILED '+fmt(sum(c['node_hours'] for c in cc if c['state']=='FAILED'),6)+'. Fuentes: filas sacct de la tabla anterior, de esta campaña.')
    add('\n- Total terminal registrado de equivalencia, humos incluidos: '+fmt(sum(c['node_hours'] for c in accounting.values()),6)+' nodo-h. Fuentes: suma sin duplicados de las filas de la tabla anterior. Es una cota al corte local registrado, no el coste final de los jobs aún no terminados en las capturas.')

    add('\n## Productos y reproducción')
    add('\nEjecutar con python3 -B analiza_xula.py --repo /ruta/al/worktree-carril-c. Solo se escriben resultados.csv e informe.md junto al script. record_type distingue run, node_summary, job_summary, diagnostic_exit0_summary, cost y coverage; los warmup y rechazos no se borran. Para examinar un nodo/ronda, filtrar run + metric=triad; las medidas MPI se identifican por los dos extremos del campo node. Las rutas de origen son relativas al worktree para evitar publicar rutas personales.')
    add('\nEste análisis no establece exclusiones definitivas ni recomienda nuevos experimentos. Resume el alcance y las observaciones de los datos ya disponibles, respetando el estudio sin privilegios.')
    (out/'informe.md').write_text('\n'.join(report)+'\n',encoding='utf-8')
    print(json.dumps(dict(jobs=len(jobs), raw_runs=len(records), checked_hashes=len(integrity),
                          effective_nodes=sorted(measured), smoke_only=sorted(smoked-measured),
                          missing_effective=missing, majority=sorted(majority),
                          node_hours=sum(c['node_hours'] for c in accounting.values()),
                          csv_rows=len(allrows)), ensure_ascii=False,indent=2))


if __name__ == '__main__':
    main()
