# Instrumentación

Dos scripts, solo bash + Python 3 stdlib. Ninguno abre conexiones SSH ni lanza jobs.
Modo de desarrollo local (macOS): `DRY_RUN=1` ejercita la ruta "no observable"
(los comandos de Linux no existen y las rutas `/sys`, `/proc` no están).

## `cmdlog.sh` — registro de comandos

Uso: `cmdlog.sh <comando> [args...]`. Ejecuta el comando, reproduce su salida
combinada (stdout+stderr) por stdout y termina con su exit code.

- `CMDLOG_DIR` (def. `$PWD/cmdlog`): raíz de salidas. `CMDLOG_RUN_ID` (opcional).
- Escribe `outputs/<sha256>.out` (salida completa) y **una** línea en
  `commands.jsonl` con: `ts`, `host`, `cmd` (argv), `tool`, `tool_path`
  (ruta resuelta del ejecutable), `tool_version`, `exit_code`, `duration_ms`,
  `out_hash`, `out_path`, `run_id`.
- **`tool_version`** se captura ejecutando `<tool_path> --version` en el entorno
  del llamante y se cachea en `tool_versions/<tool>.<hash8-de-tool_path>.txt`.
  La clave incluye la ruta resuelta: dos implementaciones con el mismo nombre
  (p. ej. `mpirun` de Open MPI y de Intel MPI en el mismo job) tienen entradas
  distintas y no se contaminan entre sí (corregido el 2026-10-04; ver
  `informes/2026-10-04-erratum-cmdlog-tool-version.md`).
- Limitación conocida: si el comando se invoca a través de un intérprete
  (`bash -lc "..."`), `tool`/`tool_version` corresponden al intérprete, no al
  binario interno; para registrarlo, invocar el binario directamente.

Es el único punto de registro: todo comando de descubrimiento/verificación pasa
por él. No tiene capacidades de consulta.

## `level1_capture.sh` — contexto de nivel 1

Uso: `level1_capture.sh {start|pre|post|stop}` alrededor del job.

- `start`: lanza en segundo plano el muestreo de frecuencia/energía cada
  `LEVEL1_INTERVAL` s (def. 1) y captura los atributos estáticos del proceso
  (modo R14, capacidades, afinidad real, fingerprint de `data/raw/discovery/`,
  variables de entorno `UCX_*`/`OMPI_*`/`I_MPI_*`/`OMP_*`/`FI_*`/`PMI_*`,
  `module list`, mpiP).
- `pre` / `post`: contadores del puerto IB antes/después (`/sys/class/infiniband/`
  sin privilegios; `perfquery` como respaldo). `post` espera `LEVEL1_IB_SETTLE` s
  (def. 2) antes de leer.
- `stop`: detiene el muestreo y escribe `CONTEXT_DIR/<run_id>.json`
  (`CONTEXT_DIR` def. `data/raw/context`), preservando el log del job y las
  muestras crudas junto al JSON.

Variables: `LEVEL1_RUN_ID` (def. `SLURM_JOB_ID`), `LEVEL1_MODE`
(`auto`|`privileged`|`unprivileged`, ver R14), `LEVEL1_CLUSTER`, `LEVEL1_NODE`,
`LEVEL1_JOB_LOG` (log del job con `UCX_LOG_LEVEL`/`I_MPI_DEBUG`/`FI_LOG_LEVEL`;
se preserva, el parseo del transporte es del notebook), `MPIP_LIB` (ruta de la
librería mpiP para `LD_PRELOAD`; si falta, se declara no disponible),
`LEVEL1_STATE_DIR`, `DISCOVERY_DIR`, `CMDLOG_DIR`.

Los comandos que invoca pasan por `cmdlog.sh` (con `CMDLOG_DIR` bajo el contexto
del run). `env`/`grep` no se envuelven a propósito, para no volcar el entorno
completo —posibles secretos— a los ficheros de salida.

### Esquema del JSON de contexto

`run_id`, `schema`, `started_at`, `stopped_at`, `node`, `cluster`, `dry_run`,
`interval_s`, `mode{level1,source}`, `capabilities{...}`, `affinity
{cpus_allowed_list,taskset,observable}`, `fingerprint{observable,source,node,path,
fingerprint}`, `env{}`, `modules{observable,list}`, `transport_log{env_vars,
log_path,observable}`, `mpip{available,lib,ld_preload}`, `job_log{observable,
log_path,preserved_path,sha256,bytes}`, `ib_counters{settle_s,source,observable,
pre,post,delta}`, `sampling{interval_s,n_samples,freq_khz{...},energy_uj{...},
samples_path,samples_sha256}` y `not_observable[]` (atributos declarados como no
observables en ese run).

En `dry_run` local, usa `CONTEXT_DIR=$(mktemp -d)` para no escribir en `data/`.
