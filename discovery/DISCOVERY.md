# Protocolo de descubrimiento

Este documento especifica **qué se comprueba, con qué comando y cómo se compara** en la fase de descubrimiento. Es la referencia para la sección correspondiente del artículo y para reproducir el descubrimiento en otro clúster (Xula, Lusitania o cualquier otro).

Todos los comandos se ejecutan a través del wrapper de registro (`instrumentation/`), que guarda comando exacto, versión de la herramienta, código de salida, duración y hash de la salida (ver AGENTS.md, *Registro de comandos*).

## 1. Principio: declarado frente a real

Cada atributo se obtiene de **dos o más fuentes**:

- **Declarado:** lo que el clúster dice de sí mismo. Configuración de Slurm (`scontrol show node`, `scontrol show config`, `sinfo`), features y GRES, documentación o catálogo del centro, `module avail`.
- **Real:** lo que se observa en el propio nodo durante un job (`lscpu`, `/sys`, `/proc`, `lstopo`, herramientas del HCA, etc.).

Se reportan tres tipos de discrepancia:

| Tipo | Qué compara | Ejemplo |
|---|---|---|
| D1. Declarado vs. real | Slurm/documentación frente al nodo | Slurm declara `ThreadsPerCore=1` y el nodo tiene SMT activo |
| D2. Real vs. real | Nodos de la misma partición entre sí | Dos nodos con versiones de firmware del HCA distintas |
| D3. Declarado vs. declarado | Fuentes declarativas entre sí | Documentación indica 1 TB por nodo y Slurm declara `RealMemory` menor |

Una discrepancia **no es un error del protocolo**: es un resultado y se conserva, aunque parezca trivial.

## 2. Ejecución

- **Nodos de cómputo:** un job por nodo, con `--exclusive` y `--nodelist=<nodo>`, de corta duración. Se recorren todos los nodos de cada partición en alcance.
- **Nodo de login:** se ejecuta también la parte de software (módulos, compiladores, MPI) para detectar diferencias entre el entorno de compilación y el de ejecución.
- **Nodos no disponibles** (drenados, caídos o reservados por otros) en el momento del descubrimiento: se registran como *no descubiertos* con su estado de Slurm y el motivo. Se reintenta una vez pasados al menos un día. Si siguen sin estar disponibles, se declaran.
- **Sin privilegios por defecto.** Los comandos que requieren root se marcan con **(root)**. Si no hay privilegios, se usa la alternativa indicada o el atributo se declara *no observable*. El modo usado se registra (R14).

## 3. Catálogo de comprobaciones

Cada fila indica la fuente declarada, la fuente real y si el atributo entra en el **fingerprint** (F), es decir, si puede influir en el rendimiento y por tanto define subparticiones. Los atributos sin F son informativos.

### 3.1 CPU y SMT

| Atributo | Declarado | Real | F |
|---|---|---|---|
| Modelo de CPU | documentación | `lscpu` (Model name), `/proc/cpuinfo` | F |
| Sockets, cores por socket | `scontrol show node` (Sockets, CoresPerSocket) | `lscpu`, `lstopo --of console` | F |
| Hilos por core (SMT/hyperthreading) | `scontrol show node` (ThreadsPerCore, CPUTot) | `cat /sys/devices/system/cpu/smt/active`, `cat /sys/devices/system/cpu/smt/control`, `lscpu` (Thread(s) per core) | F |
| CPUs lógicas en línea | `scontrol show node` (CPUTot) | `nproc --all`, `cat /sys/devices/system/cpu/online` | F |
| Microcódigo | — | `grep -m1 microcode /proc/cpuinfo` | F |
| Gobernador de frecuencia | — | `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor` (todas las CPUs) | F |
| Turbo | — | `cat /sys/devices/system/cpu/intel_pstate/no_turbo` | F |
| Rango de frecuencias | documentación | `cat /sys/devices/system/cpu/cpu0/cpufreq/{cpuinfo_min_freq,cpuinfo_max_freq}` | F |

**Nota sobre SMT.** Es el ejemplo más claro de D1: Slurm puede declarar `ThreadsPerCore=1` mientras el hardware tiene SMT activo y los hilos hermanos en línea. En ese caso, las CPUs lógicas que ve Slurm no corresponden a cores físicos, y un mapa de binding puede colocar dos ranks en el mismo core. Por eso el mapa de binding (AGENTS.md, *Binding*) se deriva siempre de la topología real (`lstopo`, `/sys/devices/system/cpu/cpu*/topology/thread_siblings_list`) y nunca de la declarada.

### 3.2 Topología NUMA y memoria

| Atributo | Declarado | Real | F |
|---|---|---|---|
| Dominios NUMA / SNC | — | `numactl -H`, `lstopo`, `lscpu` (NUMA node(s)) | F |
| Memoria total | `scontrol show node` (RealMemory), documentación | `grep MemTotal /proc/meminfo` | F |
| Población de DIMMs y velocidad | documentación | `dmidecode -t memory` **(root)**; sin root: no observable | F |
| Transparent Huge Pages | — | `cat /sys/kernel/mm/transparent_hugepage/enabled` | F |
| Balanceo NUMA automático | — | `cat /proc/sys/kernel/numa_balancing` | F |

### 3.3 Sistema y firmware

| Atributo | Declarado | Real | F |
|---|---|---|---|
| Sistema operativo | documentación | `cat /etc/os-release` | F |
| Kernel | — | `uname -r` | F |
| BIOS/firmware | — | `cat /sys/class/dmi/id/bios_version`, `cat /sys/class/dmi/id/bios_date`; con root: `dmidecode -t bios` | F |
| Modelo de servidor | documentación | `cat /sys/class/dmi/id/product_name` | — |
| Paquetería | — | `rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' \| sort \| sha256sum` (o `dpkg-query -W` \| `sort` \| `sha256sum`); lista completa guardada aparte | F (hash) |

### 3.4 Red e InfiniBand

| Atributo | Declarado | Real | F |
|---|---|---|---|
| Modelo del HCA y velocidad del puerto | documentación | `ibstat`, `ibv_devinfo` | F |
| Firmware del HCA | — | `ibstat` (Firmware version), `ibv_devinfo` (fw_ver) | F |
| Estado y velocidad negociada del puerto | — | `ibstat` (State, Rate), `cat /sys/class/infiniband/*/ports/*/rate` | F |
| Pila OFED/driver | — | `ofed_info -s` (si existe), `modinfo mlx5_core \| grep ^version` | F |
| Versión de UCX y transportes disponibles | módulos | `ucx_info -v`, `ucx_info -d` | F |
| Versión de libfabric y proveedores | módulos | `fi_info --version`, `fi_info -l` | F |
| Topología de red (grupos de switch) | `scontrol show topology` (si existe `topology.conf`) | inferida de la matriz de latencias entre pares (prueba de equivalencia): umbral = media+sd intra ×1,15. En turgalium la declarada no existe (verificado 2026-09-30); las herramientas IB (`ibnetdiscover`, `iblinkinfo`) requieren privilegios UMAD no disponibles (R14) | — |

**Nota sobre topología (DEVIATIONS 2026-09-30, E-b).** La latencia de par depende del grupo de switch de los nodos (medido: 0,92 µs intra frente a 1,36 µs cruzado en turgalium). Toda medida pt2pt (equivalencia, fase A) registra el grupo de switch de cada nodo del par; en la fase A los pares van del mismo grupo para la puntuación de R2, y los cruzados se reportan aparte. Los nodos cuya pertenencia a grupo no esté verificada por medición se marcan como no verificados.

### 3.5 Software y entorno

| Atributo | Declarado | Real | F |
|---|---|---|---|
| Módulos disponibles | `module avail` en login | `module avail` en el nodo de cómputo | — |
| Compiladores | módulos | `gcc --version`, `icx --version` (tras cargar cada módulo) | F |
| MPI | módulos | `mpirun --version` / `ompi_info`, `mpiexec --version` (Intel MPI) | F |
| MPI CUDA-aware (GPU) | módulos | `ompi_info --parsable --all \| grep mpi_built_with_cuda_support` o equivalente | — |
| Stack del CMMSE disponible | registros del CMMSE | presencia de los módulos con las versiones exactas (R5) | — |

### 3.6 Configuración de Slurm que afecta a la ejecución

Se recoge una vez por clúster, no por nodo:

| Atributo | Fuente |
|---|---|
| Plugin de tareas, afinidad y cgroups | `scontrol show config` (TaskPlugin, TaskPluginParam, ProctrackType), `cgroup.conf` si es legible |
| Selección de recursos | `scontrol show config` (SelectType, SelectTypeParameters) |
| Features y GRES por nodo | `scontrol show node` (AvailableFeatures, ActiveFeatures, Gres) |
| Definición de particiones | `scontrol show partition` |

Estos parámetros determinan si Slurm respeta el mapa de binding pedido. Si una discrepancia de afinidad (R10) aparece en la ejecución, es aquí donde se busca la primera explicación.

### 3.7 Almacenamiento

| Atributo | Declarado | Real | F |
|---|---|---|---|
| Versión del cliente Lustre | — | `lfs --version` o `cat /sys/fs/lustre/version` | — |
| Montajes | documentación | `findmnt -t lustre,nfs,gpfs` | — |
| Errores recientes del cliente | — | `dmesg -T \| grep -iE 'lustre\|LustreError'` (puede requerir privilegios según `kernel.dmesg_restrict`) o `journalctl -k` | — (R12) |

La E/S no se caracteriza (fuera de alcance), pero estos datos se recogen por su relación con cpu48c y R12.

### 3.8 GPU (solo partición GPU)

| Atributo | Declarado | Real | F |
|---|---|---|---|
| Modelo y número de GPUs | `scontrol show node` (Gres), documentación | `nvidia-smi -L` | F |
| Driver y CUDA | módulos | `nvidia-smi` (Driver Version, CUDA Version), `nvcc --version` | F |
| Topología GPU–GPU y GPU–HCA | — | `nvidia-smi topo -m` | F |
| Modo de persistencia, relojes, ECC | — | `nvidia-smi -q -d CLOCK,ECC,PERFORMANCE` | F |

## 4. Fingerprint y subparticiones

1. Para cada nodo se construye un JSON con todos los atributos.
2. El **fingerprint** es el hash de los atributos marcados con F, normalizados (orden fijo de campos, sin espacios ni marcas de tiempo).
3. Los nodos con el mismo fingerprint forman una **subpartición real**.
4. Para cada subpartición se genera una lista de nodos utilizable en `--nodelist`. Si los features de Slurm permiten seleccionarla con `--constraint`, se anota. Si no coinciden, se registra como discrepancia D1.
5. Cuando dos subparticiones difieren, el informe indica **en qué atributos** difieren, para que la subpartición tenga una explicación y no solo un hash.

Atributos informativos (sin F) nunca separan subparticiones, pero sí aparecen en la tabla de discrepancias.

## 5. Salidas

| Salida | Contenido |
|---|---|
| `data/raw/discovery/<cluster>/<nodo>.json` | Atributos del nodo |
| `data/raw/discovery/<cluster>/commands.jsonl` | Registro de comandos (wrapper) |
| `data/raw/discovery/<cluster>/outputs/` | Salidas completas, nombradas por hash |
| `data/raw/discovery/<cluster>/slurm.json` | Configuración de Slurm (3.6) |
| `data/derived/discovery/<cluster>/` | Subparticiones, listas de nodos, tabla de discrepancias D1/D2/D3 (generadas por el notebook) |

## 6. Portabilidad

El script de descubrimiento debe ejecutarse **sin modificaciones** en Xula y Lusitania (puerta de la etapa 6). Si un comando no existe en un clúster, el script registra el atributo como *no observable* y continúa; no se adapta el script al clúster. Los atributos no observables en cada clúster se reportan como parte del resultado de portabilidad.
