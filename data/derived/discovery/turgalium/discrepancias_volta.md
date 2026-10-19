# Discrepancias declarado/real - particion volta

Generado por `discovery/declared_real.py` el 2026-10-03T13:21:00Z (DISCOVERY.md secciones 1 y 5).

## D1. Declarado vs. real (por nodo)

| Nodo | Atributo | Declarado | Real |
|---|---|---|---|
| aap01 | `gpu_list` | `gpu:volta:4` | `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-a7bc4046-9fee-9525-04a7-dd2ea1dbf107...` |
| aap01 | `memory_total_kb` | `790528000` | `791213304` |
| aap02 | `gpu_list` | `gpu:volta:4` | `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-fa153924-e238-c563-29a6-0f684ad52f93...` |
| aap02 | `memory_total_kb` | `790528000` | `791213292` |
| aap03 | `gpu_list` | `gpu:volta:4` | `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-ac030ad0-cdc5-9c01-af86-b9b54b372b09...` |
| aap03 | `memory_total_kb` | `790528000` | `791213284` |
| aap04 | `gpu_list` | `gpu:volta:4` | `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-b476eef6-fdf4-5fa4-71df-2f2ae2542e53...` |
| aap04 | `memory_total_kb` | `790528000` | `791213284` |
| acp01 | `gpu_list` | `gpu:volta:2` | `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-1845713e-f5c3-66ba-7d2c-c6451a1bfe32...` |
| acp01 | `memory_total_kb` | `790528000` | `792253612` |
| acp02 | `gpu_list` | `gpu:volta:2` | `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-bb7d5c12-2f54-6a3b-2f1b-25e13547c2a2...` |
| acp02 | `memory_total_kb` | `790528000` | `791221444` |
| acp03 | `gpu_list` | `gpu:volta:2` | `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-0b634474-f0c8-6ef5-07fd-475190a62163...` |
| acp03 | `memory_total_kb` | `790528000` | `791221420` |
| acp04 | `gpu_list` | `gpu:volta:2` | `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-c51ab99d-0508-f5b7-174e-9efc03086f8c...` |
| acp04 | `memory_total_kb` | `790528000` | `791221400` |

## D2. Real vs. real (entre nodos de la particion)

- **bios_date**:
  - `05/09/2019` -> aap01, aap02, aap03, aap04
  - `11/07/2019` -> acp01, acp02, acp03, acp04
- **bios_version**:
  - `3.1` -> aap01, aap02, aap03, aap04
  - `3.2` -> acp01, acp02, acp03, acp04
- **gpu_list**:
  - `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-0b634474-f0c8-6ef5-07fd-475190a62163...` -> acp03
  - `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-1845713e-f5c3-66ba-7d2c-c6451a1bfe32...` -> acp01
  - `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-a7bc4046-9fee-9525-04a7-dd2ea1dbf107...` -> aap01
  - `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-ac030ad0-cdc5-9c01-af86-b9b54b372b09...` -> aap03
  - `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-b476eef6-fdf4-5fa4-71df-2f2ae2542e53...` -> aap04
  - `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-bb7d5c12-2f54-6a3b-2f1b-25e13547c2a2...` -> acp02
  - `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-c51ab99d-0508-f5b7-174e-9efc03086f8c...` -> acp04
  - `["GPU 0: Tesla V100-PCIE-32GB (UUID: GPU-fa153924-e238-c563-29a6-0f684ad52f93...` -> aap02
- **gpu_topology**:
  - `[4mGPU0 GPU1 GPU2 GPU3 NIC0 NIC1 CPU Affinity NUMA Affinity GPU NUMA ID[0m` -> aap01, aap02, aap03, aap04
  - `[4mGPU0 GPU1 NIC0 NIC1 CPU Affinity NUMA Affinity GPU NUMA ID[0m` -> acp01, acp02, acp03, acp04
- **hca_firmware**:
  - `["16.28.2006"]` -> aap01, aap02, aap03, acp02, acp03, acp04
  - `["16.28.2006","16.35.4506"]` -> acp01
  - `["16.35.2000"]` -> aap04
- **lustre_errors**:
  - `[Thu Apr 30 20:50:28 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> aap02
  - `[Thu Apr 30 20:50:29 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> aap03
  - `[Thu Apr 30 20:50:30 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> aap04
  - `[Thu Apr 30 20:51:03 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> aap01
  - `[Thu Apr 30 20:51:10 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> acp04
  - `[Thu Apr 30 20:51:19 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> acp01
  - `[Thu May 21 15:50:23 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu May 21 ...` -> acp03
  - `[Wed Feb 18 11:19:57 2026] Lustre: Lustre: Build Version: 2.17.0 [Wed Feb 18 ...` -> acp02
- **memory_total_kb**:
  - `791213284` -> aap03, aap04
  - `791213292` -> aap02
  - `791213304` -> aap01
  - `791221400` -> acp04
  - `791221420` -> acp03
  - `791221444` -> acp02
  - `792253612` -> acp01
- **microcode**:
  - `0x5000024` -> aap01, aap02, aap03, aap04
  - `0x500002c` -> acp01, acp02, acp03, acp04
- **mounts**:
  - `TARGET SOURCE FSTYPE OPTIONS /ws <ip>@o2ib:<ip>@o2ib:/cetafs2/...` -> aap03, acp01, acp02, acp03
  - `TARGET SOURCE FSTYPE OPTIONS /opt/apps <ip>@o2ib:<ip>@o2ib:/ce...` -> aap01, acp04
  - `TARGET SOURCE FSTYPE OPTIONS /ws <ip>@o2ib:<ip>@o2ib:/cetafs2/...` -> aap02, aap04
- **package_hash**:
  - `{"count":936,"sha256":"545d08aaa5316eced84d446f9f70afbebbc737effc76be0b7ccd14...` -> aap02, aap03, aap04, acp03, acp04
  - `{"count":932,"sha256":"6bf84d3eabd4d566894622a509bbb2ff2a484eb68d948025796991...` -> acp02
  - `{"count":937,"sha256":"2f19dd7cb89a32a6d4871d5dabc2cce85ee834e199df546dd34edf...` -> acp01
  - `{"count":938,"sha256":"6bf8c290f75df4bf1af8170d98a601ec5918e29c42d6ffb57cc382...` -> aap01

## D3. Declarado vs. declarado (slurm.json frente a nodos)

Sin discrepancias D3 detectables con las fuentes disponibles.
