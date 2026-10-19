# Discrepancias declarado/real - particion cpu112c

Generado por `discovery/declared_real.py` el 2026-10-03T13:21:00Z (DISCOVERY.md secciones 1 y 5).

## D1. Declarado vs. real (por nodo)

| Nodo | Atributo | Declarado | Real |
|---|---|---|---|
| b9p01 | `memory_total_kb` | `1024000000` | `1056475104` |
| b9p02 | `logical_cpus_online` | `112` | `224` |
| b9p02 | `memory_total_kb` | `1024000000` | `1056435000` |
| b9p02 | `threads_per_core` | `1` | `2` |
| b9p03 | `memory_total_kb` | `1024000000` | `1056475148` |
| b9p04 | `memory_total_kb` | `1024000000` | `1056475120` |
| b9p05 | `memory_total_kb` | `1024000000` | `1056473688` |
| b9p06 | `memory_total_kb` | `1024000000` | `1056475084` |
| b9p07 | `memory_total_kb` | `1024000000` | `1056475108` |
| b9p08 | `memory_total_kb` | `1024000000` | `1056475088` |
| b9p09 | `memory_total_kb` | `1024000000` | `1056475092` |
| b9p10 | `memory_total_kb` | `1024000000` | `1056473704` |
| b9p11 | `memory_total_kb` | `1024000000` | `1056473688` |
| b9p12 | `logical_cpus_online` | `112` | `224` |
| b9p12 | `memory_total_kb` | `1024000000` | `1056434064` |
| b9p12 | `threads_per_core` | `1` | `2` |
| b9p13 | `memory_total_kb` | `1024000000` | `1056473344` |
| b9p14 | `memory_total_kb` | `1024000000` | `1056473068` |
| b9p15 | `memory_total_kb` | `1024000000` | `1056473064` |
| b9p16 | `memory_total_kb` | `1024000000` | `1056473080` |

## D2. Real vs. real (entre nodos de la particion)

- **bios_date**:
  - `04/21/2025` -> b9p01, b9p02, b9p03, b9p04, b9p05, b9p06, b9p07, b9p08, b9p09, b9p10, b9p11
  - `02/28/2023` -> b9p13, b9p16
  - `10/26/2023` -> b9p14, b9p15
  - `11/10/2024` -> b9p12
- **bios_version**:
  - `R14` -> b9p01, b9p02, b9p03, b9p04, b9p05, b9p06, b9p07, b9p08, b9p09, b9p10, b9p11
  - `F14` -> b9p13, b9p16
  - `F23` -> b9p14, b9p15
  - `R10` -> b9p12
- **hca_firmware**:
  - `["20.37.1014"]` -> b9p01, b9p02, b9p03, b9p04, b9p05, b9p06, b9p07, b9p08, b9p09, b9p10, b9p11, b9p12
  - `["20.36.1010"]` -> b9p13, b9p15, b9p16
  - `["22.32.2306"]` -> b9p14
- **hca_model**:
  - `MT4123` -> b9p01, b9p02, b9p03, b9p04, b9p05, b9p06, b9p07, b9p08, b9p09, b9p10, b9p11, b9p12, b9p13, b9p15, b9p16
  - `MT4125` -> b9p14
- **logical_cpus_online**:
  - `112` -> b9p01, b9p03, b9p04, b9p05, b9p06, b9p07, b9p08, b9p09, b9p10, b9p11, b9p13, b9p14, b9p15, b9p16
  - `224` -> b9p02, b9p12
- **lustre_errors**:
  - `[Fri Jul 17 19:06:32 2026] Lustre: Lustre: Build Version: 2.17.0 [Fri Jul 17 ...` -> b9p02
  - `[Mon Aug 31 10:16:16 2026] Lustre: Lustre: Build Version: 2.17.0 [Mon Aug 31 ...` -> b9p10
  - `[Mon May 4 10:16:55 2026] Lustre: Lustre: Build Version: 2.17.0 [Mon May 4 10...` -> b9p16
  - `[Mon May 4 10:21:58 2026] Lustre: Lustre: Build Version: 2.17.0 [Mon May 4 10...` -> b9p13
  - `[Thu Apr 30 20:40:35 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> b9p01
  - `[Thu Apr 30 20:43:26 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> b9p03
  - `[Thu Apr 30 20:44:38 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> b9p05
  - `[Thu Apr 30 20:45:50 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> b9p04
  - `[Thu Apr 30 20:46:08 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> b9p07
  - `[Thu Apr 30 20:53:21 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> b9p08
  - `[Thu Apr 30 20:54:35 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> b9p09
  - `[Thu Apr 30 20:57:42 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> b9p15
  - `[Thu Apr 30 20:58:30 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> b9p14
  - `[Thu Apr 30 21:07:42 2026] Lustre: Lustre: Build Version: 2.17.0 [Thu Apr 30 ...` -> b9p11
  - `[Tue Jun 16 09:52:16 2026] Lustre: Lustre: Build Version: 2.17.0 [Tue Jun 16 ...` -> b9p06
  - `[Tue Jun 16 09:52:34 2026] Lustre: Lustre: Build Version: 2.17.0 [Tue Jun 16 ...` -> b9p12
- **memory_total_kb**:
  - `1056473688` -> b9p05, b9p11
  - `1056434064` -> b9p12
  - `1056435000` -> b9p02
  - `1056473064` -> b9p15
  - `1056473068` -> b9p14
  - `1056473080` -> b9p16
  - `1056473344` -> b9p13
  - `1056473704` -> b9p10
  - `1056475084` -> b9p06
  - `1056475088` -> b9p08
  - `1056475092` -> b9p09
  - `1056475104` -> b9p01
  - `1056475108` -> b9p07
  - `1056475120` -> b9p04
  - `1056475148` -> b9p03
- **microcode**:
  - `0x2b000639` -> b9p01, b9p02, b9p03, b9p04, b9p05, b9p06, b9p07, b9p08, b9p09, b9p10, b9p11
  - `0x2b000190` -> b9p13, b9p16
  - `0x2b0004b1` -> b9p14, b9p15
  - `0x2b000620` -> b9p12
- **mounts**:
  - `TARGET SOURCE FSTYPE OPTIONS /opt/apps <ip>@o2ib:<ip>@o2ib:/ce...` -> b9p01, b9p03, b9p04, b9p05, b9p09
  - `TARGET SOURCE FSTYPE OPTIONS /opt/apps <ip>@o2ib:<ip>@o2ib:/ce...` -> b9p08, b9p11, b9p14, b9p16
  - `TARGET SOURCE FSTYPE OPTIONS /home <ip>@o2ib:<ip>@o2ib:/cetafs...` -> b9p02, b9p12, b9p15
  - `TARGET SOURCE FSTYPE OPTIONS /ws <ip>@o2ib:<ip>@o2ib:/cetafs2/...` -> b9p07, b9p13
  - `TARGET SOURCE FSTYPE OPTIONS /home <ip>@o2ib:<ip>@o2ib:/cetafs...` -> b9p10
  - `TARGET SOURCE FSTYPE OPTIONS /ws <ip>@o2ib:<ip>@o2ib:/cetafs2/...` -> b9p06
- **server_model**:
  - `X440-E7 2U4N2S` -> b9p01, b9p02, b9p03, b9p04, b9p05, b9p06, b9p07, b9p08, b9p09, b9p10, b9p11, b9p14, b9p15
  - `H263-S64-AAW1-000` -> b9p12, b9p13, b9p16
- **threads_per_core**:
  - `1` -> b9p01, b9p03, b9p04, b9p05, b9p06, b9p07, b9p08, b9p09, b9p10, b9p11, b9p13, b9p14, b9p15, b9p16
  - `2` -> b9p02, b9p12

## D3. Declarado vs. declarado (slurm.json frente a nodos)

Sin discrepancias D3 detectables con las fuentes disponibles.
