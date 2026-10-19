# Plantillas de lanzamiento (`experiments/`)

Plantillas sbatch de las fases del experimento. Son **esqueletos con placeholders**: no se ejecutan hasta que el descubrimiento (etapa 2) y la calibración (etapa 3) proporcionen los datos reales. Ningún valor específico de clúster va incrustado: todo llega de `clusters/local.env` y de las salidas de `discovery/`.

## Convenciones comunes

- **Cola compartida, sin reservas** (DEVIATIONS 2026-09-25): todos los jobs con `--exclusive`; el presupuesto de R13 son horas acumuladas.
- **Wrapper**: todo comando de descubrimiento/verificación se lanza vía `instrumentation/cmdlog.sh` (contrato JSONL en `instrumentation/README.md`), con `CMDLOG_DIR` apuntando al directorio del run dentro de `data/raw/`.
- **Nivel 1**: cada job ejecuta `level1_capture.sh start` al comienzo y `stop` al final; contadores IB con `pre`/`post`. El modo (con/sin privilegios, R14) se fija una vez por partición y se exporta como `LEVEL1_MODE`.
- **mpiP**: el lanzador inyecta `LD_PRELOAD=$MPIP_LIB` cuando la celda lo requiera (decisión de R3); `level1_capture.sh` solo registra disponibilidad.
- **Placeholders** (dos tipos):
  - `<<<...>>>` en comentarios y directivas `#SBATCH`: sustituir a mano tras el descubrimiento (lista de nodos, partición real, mapa de binding de la topología real según DISCOVERY.md §3.1).
  - En código, los valores llegan de `clusters/local.env` vía `${VAR:?}` (fallan con mensaje claro si no están definidos): `MODULES_*`, `LEVEL1_MODE`, rutas `<CLUSTER>_SCRATCH`. No se incrustan valores de clúster en las plantillas.
- Las plantillas deben pasar `bash -n` tal cual (con placeholders); lo verificado tras sustituir es `shellcheck` + dry-run.
- **Confirmación humana**: ningún job con coste de máquina se envía sin que una persona lo apruebe en la sesión (AGENTS.md, *Ejecución en los clústeres*).

## Mapa de plantillas

| Plantilla | Fase | Reglas implicadas |
|---|---|---|
| `calib.sh` | Etapa 3: calibración | R8, R3, R13 |
| `phaseA_osu.sh` | Fase A: transporte | R2, R13 |
| `phaseB_stream_npb_hpcg.sh` | Fase B: matriz cpu112c | R1, R8, R13 |
| `anchors_hpcg_hpl.sh` | Anclas antes/después: SOLO HPCG, una sesión (HPL fuera y R6 desactivada, DEVIATIONS 2026-10-05) | R4, R5, R11 parcial |
| `infrautil.sh` | Prueba de infrautilización | R1, R10 |
| `ligero_cpu.sh` | Protocolo ligero CPU | R8, R9 |
| `ligero_gpu.sh` | Protocolo ligero GPU | R14 |
