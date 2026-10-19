# Discrepancias declarado/real - particion h100

Generado por `discovery/declared_real.py` el 2026-10-03T13:21:00Z (DISCOVERY.md secciones 1 y 5).

## D1. Declarado vs. real (por nodo)

| Nodo | Atributo | Declarado | Real |
|---|---|---|---|
| b9p17 | `gpu_list` | `gpu:H100:4` | `["GPU 0: NVIDIA H100 PCIe (UUID: GPU-f6899ccc-da1d-29c0-bfdb-d3720aaa0db2)","...` |
| b9p17 | `memory_total_kb` | `1024000000` | `1056473740` |
| b9p18 | `gpu_list` | `gpu:H100:4` | `["GPU 0: NVIDIA H100 PCIe (UUID: GPU-ac3eaf4d-62ca-9bff-5217-ddefbc13bbe0)","...` |
| b9p18 | `memory_total_kb` | `1024000000` | `1056475400` |

## D2. Real vs. real (entre nodos de la particion)

- **bios_date**:
  - `03/05/2024` -> b9p17
  - `08/07/2023` -> b9p18
- **bios_version**:
  - `F05` -> b9p18
  - `R04` -> b9p17
- **gpu_list**:
  - `["GPU 0: NVIDIA H100 PCIe (UUID: GPU-ac3eaf4d-62ca-9bff-5217-ddefbc13bbe0)","...` -> b9p18
  - `["GPU 0: NVIDIA H100 PCIe (UUID: GPU-f6899ccc-da1d-29c0-bfdb-d3720aaa0db2)","...` -> b9p17
- **lustre_errors**:
  - `[Thu Apr 16 13:31:32 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 16 ...` -> b9p17
  - `[Thu Apr 30 20:16:08 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> b9p18
- **memory_total_kb**:
  - `1056473740` -> b9p17
  - `1056475400` -> b9p18
- **microcode**:
  - `0x2b0004b1` -> b9p18
  - `0x2b000590` -> b9p17
- **mounts**:
  - `TARGET SOURCE FSTYPE OPTIONS /home <ip>@o2ib:<ip>@o2ib:/cetafs...` -> b9p17
  - `TARGET SOURCE FSTYPE OPTIONS /home <ip>@o2ib:<ip>@o2ib:/cetafs...` -> b9p18

## D3. Declarado vs. declarado (slurm.json frente a nodos)

| Particion | Comprobacion | slurm.json | Nodos (declarado) |
|---|---|---|---|
| h100 | RealMemory por nodo vs MaxMemPerNode | `786432M` | `1000000M` |
