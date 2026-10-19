#!/usr/bin/env bash
# launch/20261006-L3-ft8n-cpu36c.sh — FT-8n COMPLETO del ligero de cpu36c (D16)
#
# Objetivo:     Repetir el FT clase D a 8 nodos × 32 r/n (256) del ligero de cpu36c
#               con el pin de intel CORREGIDO, los 4 pares R2 en la MISMA asignación,
#               en CADA grupo de ejecución (SMT-off: aac112-119; SMT-on: acc112-119),
#               11 rondas (1 calentamiento + 10 efectivas), control D-B al inicio y
#               fin. Las ejecuciones 83494/83495 quedan excluidas por reetiquetado.
# Autorización: DEVIATIONS 2026-10-06 D16 (registra el envío del 2026-10-05); E64/E-f;
#               R2 de cpu36c con 7 pares (revisión de la persona, 2026-10-05).
# Scripts:      experiments/ligero36_ft8n.sbatch — commit 76a7d8091ebb0518ce57dcb673534211f434fa95
#               (v2: I_MPI_PIN=1 I_MPI_PIN_PROCESSOR_LIST="0-15,18-33" en intel,
#               idéntico a coll:intel de ligero36_osu — 16 ranks por paquete)
# Estimación:   2 jobs de 8 nodos × 01:00:00 (11 rondas × 4 pares ≈ 28 min medido en
#               83494/83495), cola compartida --exclusive, EN PARALELO (grupos de
#               nodos disjuntos).
# Humo (QA a-h): 83726 (cc-lig36-ft8n, 1 ronda, los 4 pares, aac112-119) — COMPLETED
#               2:33; sincronizado y verificado (verifica_raw 13816/13816, 0 fallos).
#               EVIDENCIA DEL PIN INTEL (QA b, map-check): mapcheck-intel-mlx.txt de
#               83726 = 256 líneas "cpus=", cada rank con UNA cpu, en bloques de 16
#               por paquete (p. ej. "aac112 rank=15 cpus=15", "aac112 rank=1 cpus=1";
#               ranks 0-15 → cpus 0-15 del paquete 0; 16-31 → cpus 18-33 del paquete 1).
#               QA: a✓ (misma forma/tamaño: 8n×256r) b✓ (map-check por par + ldd +
#               transporte observado = pedido) c✓ (SUCCESSFUL + Size clase D contra
#               salida real; caso que debe fallar: ft.B.x → FALLO ✓) d✓ (exit real;
#               patrón corregido en v2) e✓ (trazado a D16/E64/R2-7pares) f✓ g✓
#               h (este fichero).
# Dependencias: sin dependencia técnica; corre EN PARALELO con la serie cpu112c
#               (partición cpu36c) y con L4 (volta). Requiere aprobación del fichero.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261006-L3-ft8n-cpu36c.sh
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"
cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="76a7d8091ebb0518ce57dcb673534211f434fa95"
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
[ "$ACTUAL" = "$EXPECTED_COMMIT" ] || { echo "!! .deploy-commit ($ACTUAL) != commit de los scripts ($EXPECTED_COMMIT)" >&2; exit 2; }
mkdir -p data/raw/ligero

# F1: grupo SMT-off; F2: grupo SMT-on — en paralelo (nodos disjuntos)
F1="$(sbatch --parsable --nodes=8 --nodelist=aac112,aac113,aac114,aac115,aac116,aac117,aac118,aac119 \
      --time=01:00:00 experiments/ligero36_ft8n.sbatch 1 11 "gcc rc" "intel mlx" "gcc dc" "intel verbs;ofi_rxm")"
F2="$(sbatch --parsable --nodes=8 --nodelist=acc112,acc113,acc114,acc115,acc116,acc117,acc118,acc119 \
      --time=01:00:00 experiments/ligero36_ft8n.sbatch 1 11 "gcc rc" "intel mlx" "gcc dc" "intel verbs;ofi_rxm")"
echo "L3 FT-8n cpu36c lanzado: F1=$F1 F2=$F2"
