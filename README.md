# Reproducibility artefacts — *Verifying Heterogeneous Shared HPC Clusters from the User Side: A Reproducible, Cost-Aware Methodology for MPI Workloads*

Companion repository for the article submitted to *The Journal of Supercomputing* (collection "Computational and Mathematical Models using Heterogeneous Computing"):

> **Verifying Heterogeneous Shared HPC Clusters from the User Side: A Reproducible, Cost-Aware Methodology for MPI Workloads**
> José Miguel Franco-Valiente¹, Jesús Calle-Cancho², Ana Sánchez-López², Juan M. Haut³

¹ Centro Extremeño de Tecnologías Avanzadas (CETA-CIEMAT), CIEMAT, Trujillo, Spain
² Dpto. de Ingeniería de Sistemas Informáticos y Telemáticos, Universidad de Extremadura, Cáceres, Spain
³ Dpto. de Tecnología de Computadores y Comunicaciones, Universidad de Extremadura, Cáceres, Spain

It extends the CMMSE 2026 contribution (extended abstract: doi:10.5281/zenodo.23453247; artefacts: <https://github.com/josemifv/2026-CMMSE-cluster-characterisation>).

## What is here

This release contains what is needed to check and reproduce the data, tables and figures of the article:

- the **rules** fixed before the first measurement (`rules/RULES.md`) and the dated **deviation log** (`rules/DEVIATIONS.md`);
- the **measurement and launch scripts** exactly as they ran (`experiments/`, `launch/`, `discovery/`, `instrumentation/`) and the **cluster profiles** (`clusters/perfiles/`, `clusters/modulos_declarados/`, `clusters/local.env.example`);
- the **raw outputs** of every job (`data/raw/`), each command logged with its invocation, host, tool version, exit code, duration and output hash, and the **derived data** (`data/derived/`);
- the **analysis code** and the scripts that draw every figure (`analysis/`), plus a few analysis inputs and outputs kept under `informes/` (cost accounting, Xula analysis, workload table, screening sensitivity, full-Intel-stack analysis).

## Clusters

| Cluster | Operator | Partitions studied | Depth |
|---|---|---|---|
| Turgalium | CETA-CIEMAT | `cpu112c`, `cpu36c` (inventory of all partitions) | Full methodology on `cpu112c`; lightweight protocol on `cpu36c` |
| Xula | CIEMAT | `xula4` | First phase of the lightweight protocol |
| Lusitania | COMPUTAEX | `us63` (some first-phase jobs on `lusitania`) | First phase of the lightweight protocol |

All measurements were taken as an ordinary user, without privileges, reservations or special treatment.

## Layout

- `analysis/` — Analysis notebook inputs and the scripts that produce every figure of the article
- `clusters/` — Cluster profiles, declared module lists and a template for local settings (no credentials)
- `data/` — Raw outputs of every job (`raw/`, immutable) and derived data (`derived/`)
- `discovery/` — Discovery protocol and per-node inventory scripts
- `experiments/` — Job templates and scripts for each phase of the protocol
- `informes/` — Analysis inputs and outputs used by the article: cost accounting, Xula analysis, workload table, screening sensitivity and full-Intel-stack analysis (partly in Spanish)
- `instrumentation/` — Command-logging wrapper and level-1 capture
- `launch/` — Approved launch files, one `sbatch` line per job
- `rules/` — A-priori decision rules and the dated deviation log

## Figures

All scripts are in `analysis/figuras/` and are run from the repository root; the header of each states its inputs.

| Figure | Script(s) | Invocation |
|---|---|---|
| Article Fig. 1 | `fig1_niveles.py` | `python3 analysis/figuras/fig1_niveles.py .` |
| Article Fig. 2 | `extrae_fig2.py`, then `fig2_config_rend.py` | `python3 analysis/figuras/<script> .` |
| Article Fig. 3 | `fig_ft8n_allocations.py` | `python3 analysis/figuras/fig_ft8n_allocations.py <outdir>` |
| Article Fig. 4 | `extrae_fig_ficha.py`, then `fig_ficha.py` | `python3 analysis/figuras/<script> .` |
| Article Fig. 5 | `fig_t53_pinned.py` | `python3 analysis/figuras/fig_t53_pinned.py data/raw <outdir>` |
| Article Fig. 6 | `fig_red_entregada_v10i.py` | `python3 analysis/figuras/fig_red_entregada_v10i.py . [<outdir>]` |
| Online Resource 1 | `fig3_osu.py`; `extrae_fig4.py`, then `fig4_asignacion.py` | `python3 analysis/figuras/<script> .` |

Fig. 3 and the Lusitania normal-pair values of Fig. 6 are written as constants in their scripts; each constant is the median of the raw logs named in the script header and can be recomputed from `data/raw/`. `analysis/README.md` gives the canonical invocations that produce the derived data in `data/derived/`.

## Anonymisation

User names, account names and personal paths on the clusters have been replaced by placeholders (`<u>`, `<account>`, `<home>`, `<scratch>`), and private network addresses and internal file-server names by `<ip>` and `<fileserver>`; no other content was altered. The output hashes in the command logs were computed on the clusters at run time, so a file in which a placeholder was substituted no longer matches its recorded hash. `PROVENANCE.txt` records the source commit and the substitutions, and `MANIFEST.sha256` the hash of every published file. Comments and some documents are written in Spanish.

## Internal references

This release is a subset of the authors' working repository. Some comments and READMEs refer to internal files that are not published (for example `AGENTS.md`, `TASKS.md`, `informes/ordenes/`, `informes/tareas/`, `informes/estado-lineas.md` or the cluster notes `clusters/<cluster>.md`). They record how the work was organised and are not needed to reproduce the data, tables or figures.

## Licences

- Code: MIT (`LICENSE`).
- Data, documents and figures: CC BY 4.0 (`LICENSE-data`).

## How to cite

See `CITATION.cff`. Until the article is published, please cite this repository (release `v1.0-submission`) and the CMMSE 2026 extended abstract.
