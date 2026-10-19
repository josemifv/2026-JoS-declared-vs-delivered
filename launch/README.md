# Ficheros de lanzamiento (arnés de ejecución, regla 3)

Todo humo o medida se lanza desde un fichero versionado `launch/AAAAMMDD-<nombre>.sh`. La persona aprueba el fichero **por su sha256**; el agente lo ejecuta tal cual y anota hash y job IDs en el panel (`informes/estado-lineas.md`). Cualquier cambio exige un fichero nuevo y una aprobación nueva.

## Formato exigido

1. **Cabecera** (comentarios al principio del fichero):
   - Objetivo del lanzamiento.
   - Reglas de `rules/RULES.md` o entradas de `rules/DEVIATIONS.md` que lo autorizan (nunca entradas que no existan).
   - Commit de los scripts que usa (hash completo; el despliegue y `.deploy-commit` siguen la regla 9).
   - Nodos, tiempo y número de jobs estimados.
2. **Una línea `sbatch` por job**, con los parámetros reales (nodos, `--time`, exclusiones, dependencias).
3. **`cd` explícito a la raíz del checkout del clúster** en cada comando; rutas absolutas (arnés, regla 10). Ningún comando depende del directorio de trabajo de otro.
4. Validaciones previas: el script comprueba que está en el checkout correcto, que `clusters/local.env` existe y que el sha256 de cada script desplegado coincide con el commiteado antes de lanzar (regla 9, QA h).
5. El fichero se commitea ANTES de enviarse a la cola y se lanza tal cual (sin ediciones en el clúster).

## Plantilla vacía

```bash
#!/usr/bin/env bash
# launch/AAAAMMDD-<nombre>.sh
#
# Objetivo:      <qué mide o verifica este lanzamiento>
# Autorización:  <reglas de RULES.md y/o entradas de DEVIATIONS que lo autorizan>
# Scripts:       <fichero(s) de experiments/ usados, con su commit: <hash completo>>
# Estimación:    <n> jobs; <nodos por job>; <tiempo por job>; cola compartida, --exclusive
#
# Uso: bash launch/AAAAMMDD-<nombre>.sh   (desde el portátil; el cd lo hace cada sbatch)
#
# sha256 de este fichero (anotar en el panel al aprobarlo):
#   shasum -a 256 launch/AAAAMMDD-<nombre>.sh

set -euo pipefail
REPO="$TURGALIUM_REPO"                      # raíz del checkout del clúster
cd "$REPO"                                  # cd explícito (arnés, regla 10)
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env" >&2; exit 1; }
source clusters/local.env
EXPECTED_COMMIT="<hash-completo-del-commit-de-los-scripts>"
ACTUAL="$(cat .deploy-commit 2>/dev/null || true)"
[ "$ACTUAL" = "$EXPECTED_COMMIT" ] || { echo "!! .deploy-commit ($ACTUAL) != esperado ($EXPECTED_COMMIT)" >&2; exit 2; }

# <verificación previa del sha256 desplegado vs commiteado (regla 9), si procede>

# --- una línea sbatch por job ------------------------------------------------
# sbatch --nodes=<n> --exclusive --partition=<particion> --time=HH:MM:SS <exclusiones/dependencias> \
#   experiments/<script>.sbatch <argumentos>
```

## Registro

Al aprobar y lanzar: fecha y hora, sha256 del fichero, job IDs y estado se anotan en `informes/estado-lineas.md` (plantilla de la regla 8). El propio fichero de lanzamiento NO se modifica nunca tras su aprobación; un cambio requiere fichero nuevo (nuevo AAAAMMDD-<nombre>-v2.sh) y aprobación nueva.

## Índice de lanzadores

Inventario local de los 34 ficheros `.sh`; los SHA-256 son los actuales del fichero, no los de los scripts que invoca. «Lanzado» significa que Slurm aceptó los IDs indicados, no que la medida esté completa. «Sustituido» conserva el historial y no autoriza a relanzar. Las firmas se toman de `TASKS.md`; una autorización metodológica en la cabecera no es una firma de lanzamiento.

Fuentes de estado: `informes/estado-lineas.md` (preparación L1–L7 y versiones posteriores), los informes T07/T17/T18 y los informes/evidencias de las tareas de lanzamiento indicadas. Las firmas antiguas T08/T13/T15/T16 constan en `TASKS.md` sin remisión allí a una orden archivada; no se inventa esa referencia. Los estados siguientes describen el registro local, sin sondeos nuevos.

| Fichero | SHA-256 actual | Qué lanza (resumen de cabecera) | Tarea y firma/orden | Estado e IDs |
|---|---|---|---|---|
| `20261006-L1-ed-ft8n.sh` | `f4441a4d543332c95e3755fc3b10f6328930c6b3ae7a196562eede0456a71715` | FT-D ingenuo frente a recomendado a 8×64 ranks; 11 rondas repartidas en 8 jobs. | T19; sin firma en TASKS.md. | Sustituido por `20261006-L1-ed-ft8n-v2.sh`; sin IDs de este fichero en el registro. |
| `20261006-L1-ed-ft8n-v2.sh` | `0bdc63733adfc02a9ba4d657bd5d2b80efb3df21586548555732cbf0fc20cbfd` | E-d FT-D ingenuo/recomendado, puertas SHA y encadenado; 8 jobs de 8 nodos. | T19 BLOQUEADA; recomendado pendiente de decisión; sin firma. | Sin firmar. |
| `20261006-L2a-humo-ligero112.sh` | `4aa4dc80c5c2b82d9144cbb91f57b0c53d04d97d7979c0df5efeb38cdd801a1f` | Verificación de 7 combos y una ronda de colectivas/FT-8n del ligero112. | T17 (actualización posterior); sin firma de esta versión. | Sustituido por `20261006-L2a-humo-ligero112-v2.sh`. |
| `20261006-L2a-humo-ligero112-v2.sh` | `d4f1a7ee959614547798bf0f373d760081c6da14882401057b76be01b61136cb` | Humo ligero112 con puertas SHA, verificación, colectivas y FT de 4 pares. | T17; sin firma de esta versión. | Sustituido por `20261010-L2a-humo-ligero112-v3.sh`. |
| `20261006-L2b-osu112-completo.sh` | `9f8266a5350f1c2c65b5ebcb2037e4794400f29b8e7a544dd74b4e2f3882b8e1` | OSU pt2pt y colectivas de 7 pares, 11 rondas; 5 jobs. | T17 (actualización posterior); sin firma de esta versión. | Sustituido por `20261006-L2b-osu112-completo-v2.sh`. |
| `20261006-L2b-osu112-completo-v2.sh` | `9bf12fac3cc1c7379b98a1def904decc33f9068e9886e624e5018436c37127e7` | OSU propio del ligero112 con puertas SHA, pt2pt 2n y colectivas 8n. | T17; sin firma de esta versión. | Sustituido por `20261010-L2b-osu112-completo-v3.sh`. |
| `20261006-L3-ft8n-cpu36c.sh` | `ddf71fe07f15cb0f430b3d8ace7d9d1dd1a20e8a0cab69061c50c64d77faebd6` | FT-D 8×32 ranks, pin Intel corregido, 4 pares y 11 rondas por grupo. | T18 (actualización posterior); sin firma de esta versión. | Sustituido por `20261006-L3-ft8n-cpu36c-v2.sh`; 83726 es humo previo, no lanzamiento de este fichero. |
| `20261006-L3-ft8n-cpu36c-v2.sh` | `75c10157a88192631be42e828b0c482cba7cef014db667b8a9b363233f43080a` | FT-8n cpu36c de 4 pares, 2 jobs de grupos disjuntos y puertas SHA. | T18; sin firma de esta versión. | Sustituido por `20261009-L3-ft8n-cpu36c-v3.sh`. |
| `20261006-L4-cuda-osu.sh` | `f31b3a1a655753883912ab72a3c33e88e24bbfe9cc0779bbbec2a21b2957b6c9` | Compilar OSU CUDA y probar bw device-to-device entre dos GPU de un volta. | T07 (actualización posterior); sin firma de esta versión. | Sustituido por `20261006-L4-cuda-osu-v2.sh`. |
| `20261006-L4-cuda-osu-v2.sh` | `4cec76fff7316242c7731add3a13419e5dae5c3aacba82b64685f525d5ae3d15` | Prueba CUDA de 1 job, controles H H/D D y configure CUDA verificado. | T07; sin firma de esta versión. | Sustituido por `20261010-L4-cuda-osu-v3.sh`. |
| `20261006-L5-diag-ep-v2.sh` | `4ae65019b147035721ff10cc84d20622796512f96f5676904bacfc5af316265e` | Diagnóstico EP con binding de fase B, afinidad, frecuencia y utime por rank. | T07 (actualización posterior); sin firma de esta versión. | Sustituido por `20261010-L5-diag-ep-v3.sh` (cabecera T07 actualiza esta base). |
| `20261006-L5-diag-ep-v3.sh` | `fe41c24eb7bb0fcbe57335d4b53fea2c32b74f27be2e729530fa4cda02567023` | Diagnóstico EP, 64/32 ranks Intel y 64 GCC, 2 repeticiones con sondas. | T07 (actualización posterior); sin firma de esta versión. | Sustituido por `20261010-L5-diag-ep-v3.sh`; mismo sufijo, fichero distinto con sonda corregida. |
| `20261006-L6-anclas.sh` | `8bb99a8436d89429e2db0e023051730498beaf690aeee6af678f527449f80ab4` | Anclas solo HPCG: 11 rondas intercaladas CMMSE/actual, 8×56 ranks. | T08; sin firma de esta versión. | Sustituido por `20261006-L6-anclas-v2.sh`; 83799 es humo previo. |
| `20261006-L6-anclas-v2.sh` | `756283f06ea61f81cdf5a6c191af2207ac0a56da6726cf8c975c98d772110c7f` | Una sesión HPCG, 44 celdas CMMSE/actual × GCC/Intel con puertas SHA. | T08; firma APROBADO en TASKS.md (2026-10-07). | Lanzado: **84184**, T08 VERIFICADA; fuente `informes/tareas/T08/C2.txt`. |
| `20261006-L7a-humo-infrautil.sh` | `51ed554aded1c3cd244db0c11941c3a48b6762dc35d4381d03ae4abd6025bc24` | Compilación FT-C y una ronda de infrautilización en 4 nodo-grupo. | T07 (actualización posterior); sin firma de esta versión. | Sustituido por `20261006-L7a-humo-infrautil-v2.sh` (FT-D, D19). |
| `20261006-L7a-humo-infrautil-v2.sh` | `8483d78e4f82d14271d043ef42a2acf8f57fbc988a7fd0c773075b5a23fa1360` | Compilar STREAM 200M y humo FT-D/EP/STREAM en 4 nodo-grupo. | T07; sin firma de esta versión. | Sustituido por `20261010-L7a-humo-infrautil-v3.sh`. |
| `20261006-L7b-infrautil.sh` | `591b092aadb4ebde7aa7f34d64289ebb6d69a2b91108f363b39d3a03883b87be` | Infrautilización STREAM/FT-C/EP, binding default/explícito, 11 rondas. | T07 (actualización posterior); sin firma de esta versión. | Sustituido por `20261006-L7b-infrautil-v2.sh` (FT-D, D19). |
| `20261006-L7b-infrautil-v2.sh` | `812e286c0aaae2f481c8fe7d83260912a67d2d92d923b9e86c43bea164b9d354` | Infrautilización FT-D/EP/STREAM, 4 jobs; tiempo PENDIENTE-HUMO aborta. | T07; sin firma de esta versión. | Sustituido por `20261010-L7b-infrautil-v3.sh`. |
| `20261007-L8-compila-intelc.sh` | `b4a655b46a0512fbeeb6e8c7fca02acd9baa35bb1515f1ad11ec9749fc690d01` | Compilación intelc spr/clx y humo NPB/HPCG, comprobación runtime ifx original. | T12/T13; firma inicial APROBADO en TASKS.md. | Sustituido por `20261007-L8-compila-intelc-v2.sh`; histórico lanzado **84179** (fallido), **84180** (cancelado por orden); fuente informe T13. |
| `20261007-L8-compila-intelc-v2.sh` | `4be4ca19d7f7f1e1271b3839bb79b46076bb351ceb962cb8d601c9c1b4b61569` | Compilación/humo intelc con comprobación ldd corregida. | T13; firma v2 APROBADO en TASKS.md. | Lanzado: **84182** (spr fallido), **84183** (clx completo); sustituido por v3 **solo para spr**, clx conserva v2; fuente informe T13. |
| `20261007-L8-compila-intelc-v3.sh` | `b7563022709368b2b35ec6a3a53adcf29d71a6e8f93c64f80b98cc67267d35cc` | Compilación/humo intelc solo spr, tolera cp del configure HPCG según guarda. | T13; firma v3 APROBADO en TASKS.md. | Lanzado: **84185**, spr completo; T13 CERRADA; fuente `informes/tareas/T13/C2-v3.txt`. |
| `20261008-L9a-humo-faseB-intelc.sh` | `9dd2db8133eb2a352befd8103f430df160618b32535e564ecc19f1e62bf532f0` | 13 humos, una ronda EP/FT/CG/MG a 1/2/4/8n y HPCG-8n, Intel/intelc. | T14/T15; firma APROBADO en TASKS.md (T15). | Lanzado: **84446–84458**, T15 VERIFICADA; fuente `informes/tareas/T15/C2.txt`. |
| `20261008-L9b-faseB-intelc.sh` | `9fbd6eed0e655f67a1e79daa4880d21b3251513bdd7912d253b230c770fdbf03` | 13 medidas Intel/intelc, 11 rondas por carga/talla; 374 runs esperados. | T14/T16; firma APROBADO en TASKS.md (T16). | Lanzado: **84510–84522**, T16 VERIFICADA; fuente `informes/tareas/T16/C2.txt`. |
| `20261009-L10-b9p07.sh` | `52960dd0df145755eb0b0a79d64a15bd2a3b59a3333264f05c2d170059d9d15d` | Sonda de red y FT/CG-8n A/B con 5 pares; B sustituye b9p07 por b9p14. | T26/T27; APROBADO, `informes/ordenes/2026-10-09-T27-firma.md`. | Lanzado: **84616–84624**, T27 EN COLA; fuente `informes/tareas/T27-lanzamiento-L10.md`. |
| `20261009-L3-ft8n-cpu36c-v3.sh` | `e509739d58360887b55d45e72978ebfaf463ed901286406a392dce26644dab05` | Humo de 5 pares y medida FT-D en SMT-off/on; 110 runs y controles. | T18/T09/T35; firmas `informes/ordenes/2026-10-09-T09-firma.md` y `informes/ordenes/2026-10-10-T35-firma.md`. | Lanzado: humo **84615**, medida **84640/84641**; T09/T35 VERIFICADAS; fuentes informes T09 y T35. |
| `20261010-L11a-xula4-fase1.sh` | `faec5ad3cfe56825156c7448be498fea073e1ed36bb3f3768a4497827b4435fc` | Xula xula4: 28 discovery, compilación, verificación y calibración FT-8n. | T29/T30; APROBADO, `informes/ordenes/2026-10-10-T30-T31-firmas.md`; reanudación `informes/ordenes/2026-10-11-T30-T31-reanudacion.md`. | Firmado sin lanzar jobs aceptados: se ejecutó, pero los 28 envíos fueron rechazados por QoS; **sin IDs**, T30 BLOQUEADA; fuente `informes/tareas/T30/C2.txt`. |
| `20261010-L12a-lusitania-fase1.sh` | `b4255784a05f55053d8e0d11b3c1495cb25236e813e032c1d37ebe421d351256` | Lusitania: 35 discovery, compilación, verificación y calibración FT-8n. | T29/T31; APROBADO, `informes/ordenes/2026-10-10-T30-T31-firmas.md`; reanudación `informes/ordenes/2026-10-11-T30-T31-reanudacion.md`. | Lanzado: **753478–753512** discovery, **753513** compila (fallida), **753514/753515** verif/calib (cancelados en T40); T31 BLOQUEADA; fuentes `informes/tareas/T31/C2.txt`, `informes/tareas/T40/C5.txt`. |
| `20261010-L13-b9p07-discriminante.sh` | `ec32ee7e022d599e2b7c802aae3f92d9f7360a8b032ee92723820a0b4fb7ef4b` | EP/FT Intel e intelc, A/C sustituyendo b9p07 por b9p15; 4 jobs × 4 rondas. | T36/T37; APROBADO, `informes/ordenes/2026-10-10-T37-firma.md`. | Lanzado: **84643 → 84644 → 84645 → 84646**, T37 EN COLA; fuente `informes/tareas/T37/C2.txt`. |
| `20261010-L2a-humo-ligero112-v3.sh` | `d2833bd343b03b76bc7180e10aa23025b500c29131d445d2dea91928ed594301` | Humo ligero112 con intelc/mlx como quinto par FT, verificación y colectivas. | T17 VERIFICADA (preparación); sin firma. | Sin firmar. |
| `20261010-L2b-osu112-completo-v3.sh` | `321f96275abe2986489351e26606526c043598fe3b1f5fe19e31d2978e4b08a2` | OSU ligero112 pt2pt/colectivas de 7 pares, 11 rondas, puertas actuales. | T17 VERIFICADA (preparación); sin firma; requiere L2a-v3 revisado. | Sin firmar. |
| `20261010-L4-cuda-osu-v3.sh` | `e05f9ee6574361dc12d23bacedcc2c52f67f3a57bfc418aa2d2604758daad80b` | Prueba funcional OSU CUDA de 1 nodo volta, puertas actuales tras T01. | T07 VERIFICADA (preparación); sin firma. | Sin firmar. |
| `20261010-L5-diag-ep-v3.sh` | `63de27d2880837d5744669f9de6882ac1094dd17f36ff306b2f7ed14b2f044f2` | Diagnóstico EP en condiciones de fase B, frecuencia/afinidad/utime por rank. | T07 VERIFICADA (preparación); sin firma. | Sin firmar. |
| `20261010-L7a-humo-infrautil-v3.sh` | `a39d9239b43506798c0e688296bc20f5caa97243c71163044f3540faed412f54` | 4 humos de infrautilización, STREAM 200M solo GCC, FT-D/EP GCC e Intel. | T07 VERIFICADA (preparación); sin firma. | Sin firmar. |
| `20261010-L7b-infrautil-v3.sh` | `6391425f509d5b18fd46b48bb88e703f56297302020bbab74566163712e918ff` | 4 medidas de 11 rondas; STREAM solo GCC; PENDIENTE-HUMO sigue abortando. | T07 VERIFICADA (preparación); sin firma; necesita humo revisado y nuevo fichero con tiempo/firma. | Sin firmar; no es ejecutable para medir mientras conserve PENDIENTE-HUMO. |

Los humos anteriores citados en cabeceras no cuentan como IDs de estos lanzadores. T40 no dejó todavía L11a/L12a-v2 en este checkout; no se indexan ficheros ausentes ni se da por sustituida una firma por una versión aún no preparada.
