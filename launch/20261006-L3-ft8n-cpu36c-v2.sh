#!/usr/bin/env bash
# launch/20261006-L3-ft8n-cpu36c-v2.sh — FT-8n COMPLETO del ligero de cpu36c (D16)
#
# QUÉ CAMBIA RESPECTO A v1 (Prompt C 7): (1) verificación del sha256 desplegado del
# script antes de cualquier sbatch — aborta exit 4 (regla 9, QA h); (2) DEPENDE_DE;
# (3) cabecera con la declaración del diff frente al humo 83726.
# Objetivo:     Repetir el FT clase D a 8 nodos × 32 r/n (256) del ligero de cpu36c
#               con el pin de intel CORREGIDO, los 4 pares R2 en la MISMA asignación,
#               en CADA grupo de ejecución (SMT-off: aac112-119; SMT-on: acc112-119),
#               11 rondas (1 calentamiento + 10 efectivas), control D-B al inicio y
#               fin. Las ejecuciones 83494/83495 quedan excluidas por reetiquetado.
# Autorización: DEVIATIONS 2026-10-06 D16; E64/E-f; R2 de cpu36c con 7 pares
#               (revisión de la persona, 2026-10-05).
# Scripts (sha256 en el commit de referencia; regla 9):
#   experiments/ligero36_ft8n.sbatch 71f5507132cbf510ab6d67e278427da1f3578ad76b1857b835a25c5e14017fad
# DIFERENCIA frente al humo 83726 (Prompt C 7.4): el script que corrió 83726
#   (sha256=69c56bd5…, versión c6792af) difiere del actual (71f55071…) SOLO en el
#   registro de datos — `git diff c6792af..701ec01 -- experiments/ligero36_ft8n.sbatch`
#   = únicamente el bloque de trazabilidad del commit (el patrón
#   `[ -n "$REPO_COMMIT" ] || …` se sustituye por la validación de formato
#   `^[0-9a-f]{7,40}$` con fallback, líneas 39-42 actuales); NADA cambia en cómo se
#   mide ni en el pin (el pin intel 0-15,18-33 ya estaba en la versión del humo).
#   DECLARACIÓN: el grupo con SMT de cpu36c (acc112-119) NO tiene humo propio con
#   el pin corregido — el humo 83726 corrió solo en aac112-119 (SMT-off).
# Estimación:   2 jobs de 8 nodos × 01:00:00 (≈ 28 min medido), cola compartida
#               --exclusive, EN PARALELO (grupos de nodos disjuntos).
# Humo (QA a-h): 83726 (cc-lig36-ft8n, 1 ronda, los 4 pares, aac112-119) — COMPLETED
#               2:33; sincronizado y verificado (verifica_raw 13816/13816, 0 fallos).
#               Evidencia del pin intel (QA b): mapcheck-intel-mlx.txt de 83726 =
#               256 líneas cpus=, cada rank UNA cpu, bloques de 16 por paquete
#               (ranks 0-15 → cpus 0-15; 16-31 → cpus 18-33). QA: a✓ b✓ c✓ d✓ e✓
#               f✓ g✓ h✓ (este fichero).
# Dependencias: sin dependencia técnica; EN PARALELO con la serie cpu112c y con
#               L4 (volta). Encadenable con DEPENDE_DE si la persona lo desea.
# sha256 de ESTE fichero: anotado en informes/estado-lineas.md.
#
# Ejecución: ssh turgalium 'bash -s' < launch/20261006-L3-ft8n-cpu36c-v2.sh
set -euo pipefail
REPO="${TURGALIUM_REPO:-<home>}"
cd "$REPO"
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="701ec01fb042a7c9361fd884af423ae101fe421f"
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
if [ "$ACTUAL" != "$EXPECTED_COMMIT" ]; then
  echo "AVISO: .deploy-commit ($ACTUAL) != commit de referencia ($EXPECTED_COMMIT); rige el sha256 individual"
fi
check_sha() { # $1 = ruta; $2 = sha256 esperado (regla 9 / QA h) → exit 4 sin lanzar
  local real
  real="$(sha256sum "$1" | awk '{print $1}')"
  if [ "$real" != "$2" ]; then
    echo "!! sha256 desplegado de $1 NO coincide (esperado $2, real $real)" >&2
    exit 4
  fi
  echo "sha256 OK: $1"
}
check_sha experiments/ligero36_ft8n.sbatch 71f5507132cbf510ab6d67e278427da1f3578ad76b1857b835a25c5e14017fad
mkdir -p data/raw/ligero

DEP="${DEPENDE_DE:-}"
DEPOPT=""
[ -n "$DEP" ] && DEPOPT="-d afterany:$DEP"

F1="$(sbatch --parsable $DEPOPT --nodes=8 --nodelist=aac112,aac113,aac114,aac115,aac116,aac117,aac118,aac119 \
      --time=01:00:00 experiments/ligero36_ft8n.sbatch 1 11 "gcc rc" "intel mlx" "gcc dc" "intel verbs;ofi_rxm")"
F2="$(sbatch --parsable --nodes=8 --nodelist=acc112,acc113,acc114,acc115,acc116,acc117,acc118,acc119 \
      --time=01:00:00 experiments/ligero36_ft8n.sbatch 1 11 "gcc rc" "intel mlx" "gcc dc" "intel verbs;ofi_rxm")"
echo "L3-v2 FT-8n cpu36c lanzado: F1=$F1 F2=$F2"
