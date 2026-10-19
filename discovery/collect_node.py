#!/usr/bin/env python3
"""collect_node.py - inventario de descubrimiento por nodo (DISCOVERY.md).

Ejecuta el catalogo de comprobaciones de DISCOVERY.md secciones 3.1-3.8 y, para
el nodo de login, la parte de software (seccion 2). Todo comando pasa por el
wrapper instrumentation/cmdlog.sh (contrato del wrapper de registro). Parsea las
salidas y escribe un JSON por nodo con el esquema de la seccion 4: atributos
normalizados y "no observable" cuando procede.

Uso:
  python3 discovery/collect_node.py --cluster <nombre> [--mode node|login|slurm]
        [--node <nodo>] [--partition <particion>] [--out-dir DIR]
        [--wrapper PATH] [--dry-run] [--json-only]

  --mode node   (por defecto) nodo de computo: catalogo completo 3.1-3.8.
  --mode login  nodo de login: solo software (3.5).
  --mode slurm  configuracion de Slurm del cluster (3.6) -> slurm.json.

Variables de entorno que consume:
  CMDLOG_DIR               destino del registro del wrapper (por defecto <out-dir>).
  CMDLOG_RUN_ID            id de run (opcional; se genera si falta).
  DISCOVERY_OUT            out-dir por defecto si no se pasa --out-dir.
  DISCOVERY_MODULES        conjuntos de modulos a cargar antes de sondear
                           compiladores/MPI, separados por ';'
                           (ej. "gcc/12.3 openmpi/4.1.5;intel/2024.0").
  DISCOVERY_CMMSE_MODULES  modulos exactos del stack CMMSE (R5), separados por ','.
  DRY_RUN                  1 = permite el runner interno si falta el wrapper.

Portabilidad (DISCOVERY.md seccion 6): si un comando no existe o no produce dato,
el atributo se registra como "no observable" y se continua. El script no se
adapta a ningun cluster concreto.
"""

import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
import uuid

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_WRAPPER = os.path.join(REPO_ROOT, "instrumentation", "cmdlog.sh")


# --------------------------------------------------------------------------- #
# Utilidades
# --------------------------------------------------------------------------- #
def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def canon_json(obj):
    """JSON canonico: claves ordenadas, sin espacios (para el fingerprint)."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


# --------------------------------------------------------------------------- #
# Registro: consumo del wrapper instrumentation/cmdlog.sh
# --------------------------------------------------------------------------- #
class Recorder:
    """Ejecuta comandos por el wrapper y recupera su registro.

    Contrato consumido (no se crean ficheros en instrumentation/):
      cmdlog.sh <comando> [args...]  con CMDLOG_DIR / CMDLOG_RUN_ID.
      Salida completa en $CMDLOG_DIR/outputs/<sha256>.out y una linea JSON en
      $CMDLOG_DIR/commands.jsonl; el wrapper reproduce la salida por stdout.

    Si el wrapper no esta disponible y DRY_RUN=1, se usa un runner interno de
    respaldo que respeta el mismo formato (solo para la prueba local en macOS).
    """

    def __init__(self, wrapper, out_dir, run_id, node, dry_run):
        self.wrapper = wrapper
        self.dir = out_dir
        self.run_id = run_id
        self.node = node
        self.dry_run = dry_run
        self.outputs = os.path.join(out_dir, "outputs")
        self.jsonl = os.path.join(out_dir, "commands.jsonl")
        os.makedirs(self.outputs, exist_ok=True)
        self.use_wrapper = bool(wrapper) and os.path.isfile(wrapper)
        if not self.use_wrapper and not dry_run:
            raise SystemExit(
                "cmdlog.sh no encontrado en %s (usa DRY_RUN=1 para el runner interno)"
                % wrapper
            )

    def run(self, argv):
        """Ejecuta argv. Devuelve (exit_code, output_str, record_dict)."""
        if self.use_wrapper:
            return self._via_wrapper(argv)
        return self._fallback(argv)

    def _via_wrapper(self, argv):
        env = os.environ.copy()
        env["CMDLOG_DIR"] = self.dir
        env["CMDLOG_RUN_ID"] = self.run_id
        before = self._count_lines()
        try:
            proc = subprocess.run(["bash", self.wrapper] + list(argv),
                                  capture_output=True, env=env)
        except OSError:
            return self._fallback(argv)
        out = proc.stdout.decode("utf-8", "replace")
        out_hash = sha256_bytes(proc.stdout)
        rec = self._find_record(out_hash, argv, before) or self._synth(out_hash, argv, proc.returncode)
        return proc.returncode, out, rec

    def _count_lines(self):
        try:
            with open(self.jsonl, "r", encoding="utf-8") as fh:
                return sum(1 for _ in fh)
        except FileNotFoundError:
            return 0

    def _find_record(self, out_hash, argv, before):
        """Busca la linea JSON del wrapper correspondiente a esta ejecucion."""
        try:
            with open(self.jsonl, "r", encoding="utf-8") as fh:
                lines = fh.read().splitlines()
        except FileNotFoundError:
            return None
        candidates = []
        for line in lines[before:]:
            try:
                candidates.append(json.loads(line))
            except ValueError:
                continue
        for rec in candidates:                       # mejor: hash de salida
            if rec.get("out_hash") == out_hash:
                return rec
        for rec in reversed(candidates):             # alt: mismo argv
            if rec.get("cmd") == list(argv):
                return rec
        return None

    def _synth(self, out_hash, argv, code):
        return {
            "ts": utc_now(), "host": self.node, "cmd": list(argv),
            "tool": os.path.basename(argv[0]), "tool_version": None,
            "exit_code": code, "duration_ms": None, "out_hash": out_hash,
            "out_path": os.path.join(self.outputs, out_hash + ".out"),
            "run_id": self.run_id,
        }

    def _fallback(self, argv):
        tool = os.path.basename(argv[0])
        t0 = time.time()
        if shutil.which(argv[0]) is None:
            out_b = ("%s: command not found\n" % argv[0]).encode("utf-8")
            code = 127
        else:
            try:
                proc = subprocess.run(list(argv), capture_output=True)
                out_b = proc.stdout + proc.stderr
                code = proc.returncode
            except OSError as exc:
                out_b = ("%s: %s\n" % (argv[0], exc)).encode("utf-8")
                code = 126
        dur = int((time.time() - t0) * 1000)
        out_hash = sha256_bytes(out_b)
        out_path = os.path.join(self.outputs, out_hash + ".out")
        with open(out_path, "wb") as fh:
            fh.write(out_b)
        rec = {
            "ts": utc_now(), "host": self.node, "cmd": list(argv), "tool": tool,
            "tool_version": self._tool_version(tool), "exit_code": code,
            "duration_ms": dur, "out_hash": out_hash, "out_path": out_path,
            "run_id": self.run_id,
        }
        with open(self.jsonl, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
        text = out_b.decode("utf-8", "replace")
        sys.stdout.write(text)
        return code, text, rec

    def _tool_version(self, tool):
        cache_dir = os.path.join(self.dir, "tool_versions")
        os.makedirs(cache_dir, exist_ok=True)
        cache = os.path.join(cache_dir, tool + ".txt")
        if os.path.isfile(cache):
            with open(cache, "r", encoding="utf-8") as fh:
                return fh.read().strip()
        version = ""
        if shutil.which(tool):
            try:
                proc = subprocess.run([tool, "--version"], capture_output=True)
                lines = (proc.stdout or proc.stderr).decode("utf-8", "replace").splitlines()
                version = lines[0].strip() if lines else ""
            except OSError:
                version = ""
        with open(cache, "w", encoding="utf-8") as fh:
            fh.write(version + "\n")
        return version


class RawCache:
    """Ejecuta cada comando una sola vez y cachea el resultado combinado."""

    def __init__(self, recorder):
        self.recorder = recorder
        self.cache = {}

    def get(self, name, argv):
        if name not in self.cache:
            code, out, rec = self.recorder.run(argv)
            self.cache[name] = {"exit": code, "out": out, "rec": rec}
        return self.cache[name]


# --------------------------------------------------------------------------- #
# Parsers (normalizacion de valores)
# --------------------------------------------------------------------------- #
def _field(out, name):
    m = re.search(r"^\s*%s\s*:\s*(.*)$" % re.escape(name), out, re.M)
    return m.group(1).strip() if m else None


def _to_int(value):
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def p_first_nonempty(out):
    for line in out.splitlines():
        if line.strip():
            return line.strip()
    return None


def p_text(out):
    return out.strip()


def p_int(out):
    return _to_int(p_first_nonempty(out))


def p_lscpu_model(out):
    return _field(out, "Model name")


def p_cpuinfo_model(out):
    return _field(out, "model name") or _field(out, "Model name")


def p_lscpu_sockets(out):
    return _to_int(_field(out, "Socket(s)"))


def p_lscpu_cores(out):
    return _to_int(_field(out, "Core(s) per socket"))


def p_lscpu_threads(out):
    return _to_int(_field(out, "Thread(s) per core"))


def p_lscpu_numa(out):
    return _to_int(_field(out, "NUMA node(s)"))


def p_microcode(out):
    m = re.search(r"^\s*microcode\s*:\s*(\S+)", out, re.M)
    return m.group(1) if m else None


def p_cpu_range_count(out):
    text = p_first_nonempty(out)
    if not text:
        return None
    total = 0
    for part in text.split(","):
        part = part.strip()
        if "-" in part:
            lo, hi = part.split("-", 1)
            a, b = _to_int(lo), _to_int(hi)
            if a is None or b is None:
                return None
            total += b - a + 1
        elif part:
            total += 1
    return total or None


def _grep_h_values(out):
    values = []
    for line in out.splitlines():
        if ":" in line:
            values.append(line.rsplit(":", 1)[1].strip())
    return values


def p_governor_set(out):
    vals = {v for v in _grep_h_values(out) if v}
    return sorted(vals) if vals else None


def p_numactl_nodes(out):
    m = re.search(r"available:\s*(\d+)\s*nodes", out)
    return int(m.group(1)) if m else None


def p_memtotal_kb(out):
    m = re.search(r"^\s*MemTotal\s*:\s*(\d+)\s*kB", out, re.M)
    return int(m.group(1)) if m else None


def p_dimms(out):
    if not out.strip():
        return None
    count = 0
    speeds = set()
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("Size:") and "No Module" not in line:
            count += 1
        elif line.startswith("Speed:"):
            m = re.search(r"(\d+)", line)
            if m:
                speeds.add(int(m.group(1)))
    if count == 0 and not speeds:
        return None
    return {"count": count, "speeds_mts": sorted(speeds)}


def p_thp(out):
    text = p_first_nonempty(out)
    if not text:
        return None
    m = re.search(r"\[(\w+)\]", text)
    return m.group(1) if m else text


def p_os(out):
    fields = {}
    for line in out.splitlines():
        if "=" in line:
            key, val = line.split("=", 1)
            fields[key.strip()] = val.strip().strip('"')
    os_id = fields.get("ID")
    if not os_id:
        return None
    version = fields.get("VERSION_ID", "")
    return "%s-%s" % (os_id, version) if version else os_id


def p_dmi_bios_version(out):
    return _field(out, "Version")


def p_dmi_bios_date(out):
    return _field(out, "Release Date")


def p_dmi_product(out):
    return _field(out, "Product Name")


def p_pkg_hash(out):
    lines = sorted(line.strip() for line in out.splitlines() if line.strip())
    if not lines:
        return None
    digest = hashlib.sha256(("\n".join(lines) + "\n").encode("utf-8")).hexdigest()
    return {"sha256": digest, "count": len(lines)}


def p_ibstat_ca_type(out):
    m = re.search(r"^\s*CA type:\s*(.+)$", out, re.M)
    return m.group(1).strip() if m else None


def p_ibstat_fw(out):
    vals = {m.strip() for m in re.findall(r"^\s*Firmware version:\s*(.+)$", out, re.M)}
    return sorted(vals) if vals else None


def p_ibstat_state(out):
    vals = {m.strip() for m in re.findall(r"^\s*State:\s*(.+)$", out, re.M)}
    return sorted(vals) if vals else None


def p_ibstat_rate(out):
    vals = set()
    for m in re.findall(r"^\s*Rate:\s*(\d+)", out, re.M):
        vals.add(int(m))
    return sorted(vals) if vals else None


def p_ibv_ca_type(out):
    m = re.search(r"^\s*device:\s*(\S+)", out, re.M)
    return m.group(1).strip() if m else None


def p_ibv_fw(out):
    vals = {m.strip() for m in re.findall(r"^\s*fw_ver:\s*(.+)$", out, re.M)}
    return sorted(vals) if vals else None


def _ibsys_sorted_ints(out):
    vals = set()
    for m in re.findall(r":(\d+)", out):
        vals.add(int(m))
    return sorted(vals) if vals else None


def p_ibsys_state(out):
    vals = {v for v in _grep_h_values(out) if v}
    return sorted(vals) if vals else None


def p_ibsys_rate(out):
    return _ibsys_sorted_ints(out) or p_ibsys_state(out)


def p_modinfo_version(out):
    m = re.search(r"^version:\s*(.+)$", out, re.M)
    return m.group(1).strip() if m else None


def p_ucx_transports(out):
    vals = set()
    for m in re.findall(r"Transport:\s*(\S+)", out):
        vals.add(m)
    # ucx_info -d lista cada componente como "  transport: name".
    for m in re.findall(r"^\s*transport:\s*(\S+)", out, re.M):
        vals.add(m)
    return sorted(vals) if vals else None


def p_fi_providers(out):
    vals = []
    for line in out.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            vals.append(line)
    uniq = sorted(set(vals))
    return uniq if uniq else None


def p_modules_hash(out):
    lines = sorted(line.strip() for line in out.splitlines() if line.strip())
    if not lines:
        return None
    digest = hashlib.sha256(("\n".join(lines) + "\n").encode("utf-8")).hexdigest()
    return {"sha256": digest, "count": len(lines)}


def p_cuda_aware(out):
    m = re.search(r"mpi_built_with_cuda_support:\s*(\S+)", out)
    if m:
        return m.group(1)
    if not out.strip():
        return None
    return "unknown"


def p_gpu_list(out):
    lines = [ln.strip() for ln in out.splitlines() if ln.strip()]
    return lines if lines else None


def p_nvsmi_versions(out):
    driver = re.search(r"Driver Version:\s*(\S+)", out)
    cuda = re.search(r"CUDA Version:\s*(\S+)", out)
    if not driver and not cuda:
        return None
    return {
        "driver": driver.group(1) if driver else None,
        "cuda": cuda.group(1) if cuda else None,
    }


def p_gpu_settings(out):
    if not out.strip():
        return None
    settings = {}
    persistence = re.search(r"Persistence Mode\s*:\s*(\S+)", out)
    if persistence:
        settings["persistence"] = persistence.group(1)
    ecc = re.search(r"ECC Mode\s*\n?\s*Current\s*:\s*(\S+)", out)
    if ecc:
        settings["ecc_current"] = ecc.group(1)
    clocks = {}
    for key in ("SM", "Memory", "Graphics"):
        m = re.search(r"Max Clocks.*?\n(?:.*\n)*?\s*%s\s*:\s*(\d+)" % key, out)
        if m:
            clocks[key.lower()] = int(m.group(1))
    if clocks:
        settings["max_clocks_mhz"] = clocks
    return settings or None


# --- declarado desde scontrol ----------------------------------------------- #
def scontrol_kv(out):
    """Pares clave=valor de scontrol.

    Soporta los dos formatos: show config (una pareja por linea, clave alineada
    con espacios antes de '=') y show node (varias parejas por linea). El valor
    acaba al final de la linea o donde empieza la siguiente pareja de la misma.
    """
    values = {}
    pairs = list(re.finditer(r"([A-Za-z0-9_@.()]+)\s*=\s*", out))
    for i, m in enumerate(pairs):
        line_end = out.find("\n", m.end())
        if line_end == -1:
            line_end = len(out)
        next_start = pairs[i + 1].start() if i + 1 < len(pairs) else len(out)
        values[m.group(1)] = out[m.end():min(line_end, next_start)].strip()
    return values


def p_sc(key, conv=str):
    def parse(out):
        kv = scontrol_kv(out)
        return conv(kv[key]) if key in kv else None
    return parse


def p_sc_features(out):
    kv = scontrol_kv(out)
    raw = kv.get("AvailableFeatures") or kv.get("ActiveFeatures")
    if not raw or raw == "(null)":
        return None
    return sorted(f for f in raw.split(",") if f and f != "(null)")


def p_sc_gres(out):
    kv = scontrol_kv(out)
    return kv.get("Gres") or None


def p_cmmse(out):
    # Stub: collect_node() lo sustituye por cmmse_parser() con la lista de
    # modulos configurada en DISCOVERY_CMMSE_MODULES (R5).
    return None


def S(raw, parse, ok_exit=(0,)):
    return {"raw": raw, "parse": parse, "ok_exit": ok_exit}


# --------------------------------------------------------------------------- #
# Comandos crudos (todos via wrapper)
# --------------------------------------------------------------------------- #
RAW = {
    "lscpu": ["lscpu"],
    "cpuinfo": ["cat", "/proc/cpuinfo"],
    "smt_active": ["cat", "/sys/devices/system/cpu/smt/active"],
    "smt_control": ["cat", "/sys/devices/system/cpu/smt/control"],
    "nproc_all": ["nproc", "--all"],
    "cpus_online": ["cat", "/sys/devices/system/cpu/online"],
    "governor": ["bash", "-c",
                 "grep -H . /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"],
    "no_turbo": ["cat", "/sys/devices/system/cpu/intel_pstate/no_turbo"],
    "freq_min": ["cat", "/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq"],
    "freq_max": ["cat", "/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"],
    "numactl_h": ["numactl", "-H"],
    "meminfo": ["cat", "/proc/meminfo"],
    "dmidecode_mem": ["dmidecode", "-t", "memory"],
    "dmidecode_bios": ["dmidecode", "-t", "bios"],
    "thp": ["cat", "/sys/kernel/mm/transparent_hugepage/enabled"],
    "numa_balancing": ["cat", "/proc/sys/kernel/numa_balancing"],
    "os_release": ["cat", "/etc/os-release"],
    "uname_r": ["uname", "-r"],
    "bios_version": ["cat", "/sys/class/dmi/id/bios_version"],
    "bios_date": ["cat", "/sys/class/dmi/id/bios_date"],
    "product_name": ["cat", "/sys/class/dmi/id/product_name"],
    "rpm_qa": ["rpm", "-qa", "--qf", "%{NAME}-%{VERSION}-%{RELEASE}\\n"],
    "dpkg_query": ["dpkg-query", "-W"],
    "ibstat": ["ibstat"],
    "ibv_devinfo": ["ibv_devinfo"],
    "ib_port_rate": ["bash", "-c", "grep -H . /sys/class/infiniband/*/ports/*/rate"],
    "ib_port_state": ["bash", "-c", "grep -H . /sys/class/infiniband/*/ports/*/state"],
    "ofed_info": ["ofed_info", "-s"],
    "modinfo_mlx5": ["modinfo", "mlx5_core"],
    "ucx_info_v": ["ucx_info", "-v"],
    "ucx_info_d": ["ucx_info", "-d"],
    "fi_info_version": ["fi_info", "--version"],
    "fi_info_list": ["fi_info", "-l"],
    "module_avail": ["bash", "-lc", "module avail"],
    "module_list": ["bash", "-lc", "module list"],
    "gcc_version": ["gcc", "--version"],
    "icx_version": ["icx", "--version"],
    "mpirun_version": ["mpirun", "--version"],
    "ompi_info_version": ["ompi_info", "--version"],
    "mpiexec_version": ["mpiexec", "--version"],
    "ompi_info_parsable": ["ompi_info", "--parsable", "--all"],
    "lustre_lfs": ["lfs", "--version"],
    "lustre_sys": ["cat", "/sys/fs/lustre/version"],
    "findmnt": ["findmnt", "-t", "lustre,nfs,gpfs"],
    "dmesg_lustre": ["bash", "-c", "dmesg -T | grep -iE 'lustre|LustreError'"],
    "journalctl_lustre": ["bash", "-c", "journalctl -k | grep -iE 'lustre|LustreError'"],
    "nvidia_smi_L": ["nvidia-smi", "-L"],
    "nvidia_smi": ["nvidia-smi"],
    "nvcc_version": ["nvcc", "--version"],
    "nvidia_smi_topo": ["nvidia-smi", "topo", "-m"],
    "nvidia_smi_q": ["nvidia-smi", "-q", "-d", "CLOCK,ECC,PERFORMANCE"],
    "scontrol_config": ["scontrol", "show", "config"],
    "scontrol_partition": ["scontrol", "show", "partition"],
}


# --------------------------------------------------------------------------- #
# Catalogo de comprobaciones (DISCOVERY.md 3.1-3.8). F = entra en el fingerprint.
# --------------------------------------------------------------------------- #
CHECKS = [
    # 3.1 CPU y SMT
    {"key": "cpu_model", "F": True,
     "real": [S("lscpu", p_lscpu_model), S("cpuinfo", p_cpuinfo_model)]},
    {"key": "sockets", "F": True,
     "real": [S("lscpu", p_lscpu_sockets)],
     "declared": [S("scontrol_node", p_sc("Sockets", int))]},
    {"key": "cores_per_socket", "F": True,
     "real": [S("lscpu", p_lscpu_cores)],
     "declared": [S("scontrol_node", p_sc("CoresPerSocket", int))]},
    {"key": "threads_per_core", "F": True,
     "real": [S("lscpu", p_lscpu_threads), S("smt_active", p_int)],
     "declared": [S("scontrol_node", p_sc("ThreadsPerCore", int))]},
    {"key": "logical_cpus_online", "F": True,
     "real": [S("nproc_all", p_int), S("cpus_online", p_cpu_range_count)],
     "declared": [S("scontrol_node", p_sc("CPUTot", int))]},
    {"key": "microcode", "F": True, "real": [S("cpuinfo", p_microcode)]},
    {"key": "scaling_governor", "F": True, "real": [S("governor", p_governor_set)]},
    {"key": "no_turbo", "F": True, "real": [S("no_turbo", p_int)]},
    {"key": "freq_min_khz", "F": True, "real": [S("freq_min", p_int)]},
    {"key": "freq_max_khz", "F": True, "real": [S("freq_max", p_int)]},
    # 3.2 Topologia NUMA y memoria
    {"key": "numa_nodes", "F": True,
     "real": [S("numactl_h", p_numactl_nodes), S("lscpu", p_lscpu_numa)]},
    {"key": "memory_total_kb", "F": True,
     "real": [S("meminfo", p_memtotal_kb)],
     "declared": [S("scontrol_node", p_sc("RealMemory", lambda v: int(v) * 1024))]},
    {"key": "dimm_population", "F": True, "real": [S("dmidecode_mem", p_dimms)]},
    {"key": "thp_enabled", "F": True, "real": [S("thp", p_thp)]},
    {"key": "numa_balancing", "F": True, "real": [S("numa_balancing", p_int)]},
    # 3.3 Sistema y firmware
    {"key": "os", "F": True, "real": [S("os_release", p_os)]},
    {"key": "kernel", "F": True, "real": [S("uname_r", p_first_nonempty)]},
    {"key": "bios_version", "F": True,
     "real": [S("dmidecode_bios", p_dmi_bios_version),
              S("bios_version", p_first_nonempty)]},
    {"key": "bios_date", "F": True,
     "real": [S("dmidecode_bios", p_dmi_bios_date), S("bios_date", p_first_nonempty)]},
    {"key": "server_model", "F": False,
     "real": [S("product_name", p_first_nonempty), S("dmidecode_bios", p_dmi_product)]},
    {"key": "package_hash", "F": True,
     "real": [S("rpm_qa", p_pkg_hash), S("dpkg_query", p_pkg_hash)]},
    # 3.4 Red e InfiniBand
    {"key": "hca_model", "F": True,
     "real": [S("ibstat", p_ibstat_ca_type), S("ibv_devinfo", p_ibv_ca_type)]},
    {"key": "hca_firmware", "F": True,
     "real": [S("ibstat", p_ibstat_fw), S("ibv_devinfo", p_ibv_fw)]},
    {"key": "port_state", "F": True,
     "real": [S("ibstat", p_ibstat_state), S("ib_port_state", p_ibsys_state)]},
    {"key": "port_rate", "F": True,
     "real": [S("ibstat", p_ibstat_rate), S("ib_port_rate", p_ibsys_rate)]},
    {"key": "ofed_version", "F": True,
     "real": [S("ofed_info", p_first_nonempty), S("modinfo_mlx5", p_modinfo_version)]},
    {"key": "ucx_version", "F": True, "real": [S("ucx_info_v", p_first_nonempty)]},
    {"key": "ucx_transports", "F": True, "real": [S("ucx_info_d", p_ucx_transports)]},
    {"key": "libfabric_version", "F": True,
     "real": [S("fi_info_version", p_first_nonempty)]},
    {"key": "libfabric_providers", "F": True, "real": [S("fi_info_list", p_fi_providers)]},
    # 3.5 Software y entorno
    {"key": "modules_avail", "F": False, "real": [S("module_avail", p_modules_hash)]},
    {"key": "gcc_version", "F": True, "real": [S("gcc_version", p_first_nonempty)]},
    {"key": "icx_version", "F": True, "real": [S("icx_version", p_first_nonempty)]},
    {"key": "openmpi_version", "F": True,
     "real": [S("mpirun_version", p_first_nonempty),
              S("ompi_info_version", p_first_nonempty)]},
    {"key": "intelmpi_version", "F": True,
     "real": [S("mpiexec_version", p_first_nonempty)]},
    {"key": "mpi_cuda_aware", "F": False, "real": [S("ompi_info_parsable", p_cuda_aware)]},
    {"key": "cmmse_stack", "F": False, "real": [S("module_avail", p_cmmse)]},
    # 3.6 Configuracion de Slurm (parte declarada por nodo)
    {"key": "slurm_features", "F": False, "declared": [S("scontrol_node", p_sc_features)]},
    {"key": "slurm_gres", "F": False, "declared": [S("scontrol_node", p_sc_gres)]},
    # 3.7 Almacenamiento
    {"key": "lustre_version", "F": False,
     "real": [S("lustre_lfs", p_first_nonempty), S("lustre_sys", p_first_nonempty)]},
    {"key": "mounts", "F": False, "real": [S("findmnt", p_text, (0, 1))]},
    {"key": "lustre_errors", "F": False,
     "real": [S("dmesg_lustre", p_text, (0, 1)),
              S("journalctl_lustre", p_text, (0, 1))]},
    # 3.8 GPU (solo particion GPU; se intenta siempre y se declara si no existe)
    {"key": "gpu_list", "F": True,
     "real": [S("nvidia_smi_L", p_gpu_list)],
     "declared": [S("scontrol_node", p_sc_gres)]},
    {"key": "gpu_driver_cuda", "F": True, "real": [S("nvidia_smi", p_nvsmi_versions)]},
    {"key": "gpu_topology", "F": True, "real": [S("nvidia_smi_topo", p_first_nonempty)]},
    {"key": "gpu_settings", "F": True, "real": [S("nvidia_smi_q", p_gpu_settings)]},
]

SOFTWARE_KEYS = {
    "modules_avail", "gcc_version", "icx_version", "openmpi_version",
    "intelmpi_version", "mpi_cuda_aware", "cmmse_stack",
}


# --------------------------------------------------------------------------- #
# Evaluacion de atributos
# --------------------------------------------------------------------------- #
def eval_sources(sources, rawget):
    reasons = []
    for src in sources:
        entry = rawget(src["raw"])
        if entry["exit"] not in src.get("ok_exit", (0,)):
            reasons.append("%s: exit %d" % (src["raw"], entry["exit"]))
            continue
        try:
            value = src["parse"](entry["out"])
        except Exception:
            reasons.append("%s: error de parseo" % src["raw"])
            continue
        if value is None:
            reasons.append("%s: sin dato" % src["raw"])
            continue
        rec = entry["rec"] or {}
        return {
            "observable": True,
            "value": value,
            "cmd": rec.get("cmd"),
            "out_hash": rec.get("out_hash"),
            "out_path": rec.get("out_path"),
        }
    return {"observable": False, "reason": "; ".join(reasons) or "sin fuente"}


def needed_raw(checks):
    names = set()
    for chk in checks:
        for src in chk.get("real", []) + chk.get("declared", []):
            names.add(src["raw"])
    return names


def build_module_probes(modules_env):
    """Genera sondas de compiladores/MPI cargando cada conjunto de modulos."""
    raw, checks = {}, []
    sets = [s.strip() for s in modules_env.split(";") if s.strip()]
    for idx, mod_set in enumerate(sets):
        for tool, key in (("gcc", "gcc_version"), ("icx", "icx_version"),
                          ("mpirun", "openmpi_version"), ("mpiexec", "intelmpi_version")):
            name = "mod%d_%s" % (idx, tool)
            raw[name] = ["bash", "-lc",
                         "module load %s >/dev/null 2>&1; %s --version" % (mod_set, tool)]
            checks.append({"key": "%s@mod%d" % (key, idx), "F": False,
                           "real": [S(name, p_first_nonempty)]})
    return raw, checks


def cmmse_parser():
    modules = [m.strip() for m in os.environ.get("DISCOVERY_CMMSE_MODULES", "").split(",")
               if m.strip()]

    def parse(out):
        if not modules:
            return None
        available = out
        return {mod: (mod in available) for mod in modules}
    return parse


# --------------------------------------------------------------------------- #
# Modos
# --------------------------------------------------------------------------- #
def collect_node(args):
    node = args.node or os.environ.get("SLURMD_NODENAME") or socket.gethostname().split(".")[0]
    run_id = os.environ.get("CMDLOG_RUN_ID") or "%s-%s" % (
        node, uuid.uuid4().hex[:8])
    out_dir = args.out_dir
    os.makedirs(out_dir, exist_ok=True)

    recorder = Recorder(args.wrapper, out_dir, run_id, node, args.dry_run)
    rawget = RawCache(recorder)

    checks = list(CHECKS)
    if args.mode == "login":
        checks = [c for c in checks if c["key"] in SOFTWARE_KEYS]
    # cmmse_stack necesita el parser con la lista de modulos configurada.
    for chk in checks:
        if chk["key"] == "cmmse_stack":
            chk["real"] = [S("module_avail", cmmse_parser())]

    extra_raw, extra_checks = build_module_probes(os.environ.get("DISCOVERY_MODULES", ""))
    RAW.update(extra_raw)
    if args.mode == "login":
        extra_checks = [c for c in extra_checks
                        if c["key"].split("@")[0] in SOFTWARE_KEYS]
    checks.extend(extra_checks)

    # scontrol show node <nodo> (declarado). El nombre del nodo es dinamico.
    dynamic_raw = {}
    if any(src["raw"] == "scontrol_node"
           for chk in checks for src in chk.get("real", []) + chk.get("declared", [])):
        dynamic_raw["scontrol_node"] = ["scontrol", "show", "node", node]

    rawget_named = {}
    for name in needed_raw(checks):
        argv = dynamic_raw.get(name) or RAW.get(name)
        if argv is None:
            continue
        rawget_named[name] = argv

    def get(name):
        return rawget.get(name, rawget_named[name])

    attributes = {}
    for chk in checks:
        attr = {"F": chk["F"]}
        if chk.get("real"):
            attr["real"] = eval_sources(chk["real"], get)
        if chk.get("declared"):
            attr["declared"] = eval_sources(chk["declared"], get)
        attributes[chk["key"]] = attr

    fingerprint_attrs = [c["key"] for c in checks if c["F"]]
    # TODO(no cubierto por RULES.md): no hay regla que fije como tratar un
    # atributo F "no observable" en el fingerprint. Se usa null y se documenta;
    # estan pendientes de decision humana. Ver rules/DEVIATIONS.md.
    fingerprint_values = {}
    for key in fingerprint_attrs:
        real = attributes[key].get("real", {})
        fingerprint_values[key] = real.get("value") if real.get("observable") else None
    # Hash de los atributos F normalizados (§4): orden fijo, sin espacios ni
    # marcas de tiempo. Siempre presente, aunque en dry-run quede vacio.
    fingerprint = sha256_bytes(canon_json(fingerprint_values).encode("utf-8"))

    doc = {
        "schema_version": 1,
        "cluster": args.cluster,
        "node": node,
        "role": args.mode,
        "partition": args.partition,
        "collected_at": utc_now(),
        "run_id": run_id,
        "collector": {
            "wrapper": args.wrapper if recorder.use_wrapper else "internal-fallback",
            "dry_run": bool(args.dry_run),
        },
        "fingerprint": fingerprint,
        "fingerprint_attrs": fingerprint_attrs,
        "fingerprint_values": fingerprint_values,
        "attributes": attributes,
    }

    path = os.path.join(out_dir, node + ".json")
    if not args.json_only:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(doc, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        sys.stderr.write("collect_node: escrito %s (fingerprint=%s, attrs=%d)\n"
                         % (path, fingerprint[:12], len(fingerprint_attrs)))
    else:
        json.dump(doc, sys.stdout, indent=2, ensure_ascii=False)
        sys.stdout.write("\n")
    return 0


def parse_partitions(out):
    blocks, current = [], None
    for line in out.splitlines():
        if line.strip().startswith("PartitionName="):
            if current:
                blocks.append(current)
            current = {}
        if current is not None:
            for m in re.finditer(r"(\w+)=(\S+)", line):
                current[m.group(1)] = m.group(2)
    if current:
        blocks.append(current)
    return blocks


# DISCOVERY.md 3.6: claves que la configuracion de Slurm debe contener para que
# el bloque se considere observable; un parser que solo captura parte de la
# salida no debe marcar el bloque como observable.
SLURM_REQUIRED_KEYS = ("TaskPlugin", "TaskPluginParam", "ProctrackType",
                       "SelectType", "SelectTypeParameters", "MpiDefault")


def collect_slurm(args):
    run_id = os.environ.get("CMDLOG_RUN_ID") or "slurm-%s" % uuid.uuid4().hex[:8]
    out_dir = args.out_dir
    os.makedirs(out_dir, exist_ok=True)
    recorder = Recorder(args.wrapper, out_dir, run_id, args.node or "login", args.dry_run)
    cfg = recorder.run(RAW["scontrol_config"])
    part = recorder.run(RAW["scontrol_partition"])
    cfg_kv = scontrol_kv(cfg[1]) if cfg[0] == 0 else {}
    doc = {
        "schema_version": 1,
        "cluster": args.cluster,
        "role": "slurm",
        "collected_at": utc_now(),
        "run_id": run_id,
        "config": cfg_kv,
        "partitions": parse_partitions(part[1]) if part[0] == 0 else [],
        "raw": {"config": cfg[2], "partition": part[2]},
        "observable": {
            # observable exige exit 0 Y la presencia de las claves de 3.6
            "config": cfg[0] == 0 and all(k in cfg_kv for k in SLURM_REQUIRED_KEYS),
            "partition": part[0] == 0,
        },
    }
    path = os.path.join(out_dir, "slurm.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    sys.stderr.write("collect_node: escrito %s\n" % path)
    return 0


# --------------------------------------------------------------------------- #
def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Inventario de descubrimiento por nodo (DISCOVERY.md).")
    parser.add_argument("--cluster", required=True, help="nombre del cluster")
    parser.add_argument("--mode", default="node", choices=["node", "login", "slurm"])
    parser.add_argument("--node", default=None, help="nombre del nodo")
    parser.add_argument("--partition", default=None, help="particion declarada")
    parser.add_argument("--out-dir", default=None,
                        help="directorio de salida (por defecto DISCOVERY_OUT o "
                             "<repo>/data/raw/discovery/<cluster>)")
    parser.add_argument("--wrapper", default=DEFAULT_WRAPPER,
                        help="ruta a instrumentation/cmdlog.sh")
    parser.add_argument("--dry-run", action="store_true",
                        help="permite el runner interno si falta el wrapper")
    parser.add_argument("--json-only", action="store_true",
                        help="escribe el JSON por stdout (sin fichero)")
    args = parser.parse_args(argv)

    if args.out_dir is None:
        args.out_dir = os.environ.get("DISCOVERY_OUT") or os.path.join(
            REPO_ROOT, "data", "raw", "discovery", args.cluster)
    args.dry_run = args.dry_run or os.environ.get("DRY_RUN") == "1"

    if args.mode == "slurm":
        return collect_slurm(args)
    return collect_node(args)


if __name__ == "__main__":
    sys.exit(main())
