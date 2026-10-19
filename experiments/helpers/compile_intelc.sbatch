#!/usr/bin/env bash
#SBATCH --job-name=compile-intelc
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --exclusive
#SBATCH --account=<account>
#SBATCH --time=01:30:00
#SBATCH --output=data/raw/intelc/compile-intelc-%j.out

# Compilación y humo de la pila intelc (D21: Intel MPI 2021.17 + compiladores de
# intel/2025.3.2 — ifx para NPB, icpx para HPCG; tarea T12 de TASKS.md). Un job
# por arquitectura: <arch> = spr (cpu112c) | clx (cpu36c); el nodo lo fija el
# lanzamiento (L8: spr con --exclude=b9p02,b9p12; clx en el grupo SMT-off,
# representante aac102). Patrón de los demás helpers (compile_phaseB.sbatch):
# fuentes de NPB 3.4.1 y HPCG 3.1.0 de la fase B, wrapper cmdlog, salida a
# data/raw/ y SIN rutas /home literales (solo $HOME y $TURGALIUM_*).
#
# Fases del job:
#   1. Sonda: which + --version de ifx, icx, icpx, mpiifx, mpiicx y mpiicpx a
#      un fichero. Sin ifx o sin mpiifx → exit 10 (SIN-IFX), SIN compilar
#      nada (dato para la persona: el módulo no trae compilador Fortran).
#   2. NPB 3.4.1 (la MISMA fuente que la fase B): ft, ep, cg y mg clase D con
#      MPIFC=mpiifx y FFLAGS=-O3 -march=<arch>, SIN los flags propios de
#      gfortran (-fallow-argument-mismatch -fallow-invalid-boz). Árbol de
#      build NUEVO por ejecución (sin binarios viejos relabeled, lección
#      83301/83312). Si ifx no acepta -march=<arch>, el make falla y el job
#      aborta con el log: NO se prueban flags alternativos (orden de la
#      persona, T12). Destino: benchmarks/npb/intelc/<arch>/.
#   3. HPCG 3.1.0, SOLO spr: mpiicpx con -DHPCG_NO_OPENMP -O3
#      -march=sapphirerapids (los flags de la fase B). Destino:
#      benchmarks/phaseB/hpcg/intelc/xhpcg.
#   4. Por cada binario: ldd a fichero — debe incluir las librerías de
#      ejecución de ifx (libimf y libintlc) en los NPB y el libmpi.so.12 de
#      Intel MPI en todos — y sha256sum a un fichero común. El runtime
#      Fortran de ifx se enlaza estáticamente por defecto y NO aparece en el
#      ldd (data/raw/intelc/compile-intelc-84179/ldd-npb-ft-spr.txt).
#   5. Humo EN EL MISMO JOB, con la forma de la celda de 1 nodo de la fase B
#      para intel/mlx: spr → 64 ranks, I_MPI_PIN_PROCESSOR_LIST=0-31,56-87,
#      FI_PROVIDER=mlx; clx → 32 ranks, 0-15,18-33. Cada NPB debe dar
#      Verification = SUCCESSFUL y Class = D (NPB imprime ambas líneas en
#      todos los kernels; comprobado contra los logs de EP de 83800); FT
#      exige además el Size de clase D 2048x1024x1024 (D19; la pareja
#      SUCCESSFUL sola NO distingue clase — calib36: lección 83301/83312).
#      CG/MG registran además su línea Size para auditoría. HPCG debe dar
#      VALID con exit 0, verificado por el HPCG-Benchmark_*.txt del rundir
#      (este binario no escribe el resultado por stdout; observación de la
#      fase B, job 83403). Si alguna verificación falla, el job termina en
#      fallo (exit 6) con el manifiesto completo como evidencia.
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}" || exit 1
[ -f clusters/local.env ] || { echo "!! falta clusters/local.env en $(pwd)" >&2; exit 1; }
source clusters/local.env
ARCH="${1:?uso: sbatch [-p particion] compile_intelc.sbatch <arch: spr|clx>}"
case "$ARCH" in
  spr) MARCH=sapphirerapids ;;
  clx) MARCH=cascadelake ;;
  *) echo "!! arch desconocida: $ARCH (spr|clx)" >&2; exit 2 ;;
esac
# La pila de la asignación debe coincidir con la arch pedida (los mapas del
# humo dependen de ella; spr exige los nodos SMT-off de cpu112c).
case "$ARCH:${SLURM_JOB_PARTITION:-}" in
  spr:cpu112c|clx:cpu36c) ;;
  *) echo "!! arch $ARCH exige su partición (spr→cpu112c, clx→cpu36c); asignación: ${SLURM_JOB_PARTITION:-ninguna}" >&2; exit 2 ;;
esac

W="$PWD/instrumentation/cmdlog.sh"
[ -x "$W" ] || { echo "!! falta wrapper $W" >&2; exit 3; }
export CMDLOG_DIR="$TURGALIUM_SCRATCH/cc/raw/intelc/compile-intelc-$SLURM_JOB_ID"
export CMDLOG_RUN_ID="compile-intelc-$ARCH-$SLURM_JOB_ID"
export LEVEL1_MODE="unprivileged"   # R14
mkdir -p "$CMDLOG_DIR" data/raw/intelc "$TURGALIUM_SCRATCH/src/intelc"

# ---- 1) sonda de compiladores (SIN-IFX: exit 10 sin compilar nada) ---------
module purge 2>/dev/null || true
module load intel/2025.3.2
SONDA="$CMDLOG_DIR/sonda-versiones-$ARCH.txt"
: > "$SONDA"
for t in ifx icx icpx mpiifx mpiicx mpiicpx; do
  {
    echo "== $t: $(command -v "$t" || echo NO-ENCONTRADO)"
    "$t" --version 2>&1 | head -2 || true
  } >> "$SONDA"
done
cat "$SONDA"
command -v ifx    >/dev/null 2>&1 || { echo "SIN-IFX: ifx no está en intel/2025.3.2 (sonda: $SONDA)" >&2; exit 10; }
command -v mpiifx >/dev/null 2>&1 || { echo "SIN-IFX: mpiifx no está en intel/2025.3.2 (sonda: $SONDA)" >&2; exit 10; }

NPB_SRC="$TURGALIUM_SCRATCH/src/NPB3.4.1/NPB3.4-MPI"
HPCG_SRC="$HOME/CMMSE26/benchmarks/hpcg/src/hpcg-HPCG-release-3-1-0"
[ -d "$NPB_SRC" ] || { echo "!! falta fuente NPB: $NPB_SRC" >&2; exit 1; }
INTELC_NPB="$TURGALIUM_SCRATCH/benchmarks/npb/intelc/$ARCH"
INTELC_HPCG="$TURGALIUM_SCRATCH/benchmarks/phaseB/hpcg/intelc"
SHAFILE="$CMDLOG_DIR/sha256-binarios-$ARCH.txt"
: > "$SHAFILE"

# ---- 2) NPB 3.4.1: ft, ep, cg, mg clase D con ifx ---------------------------
NPB_BUILD="$TURGALIUM_SCRATCH/src/intelc/npb-intelc-$ARCH"
rm -rf "$NPB_BUILD"; cp -r "$NPB_SRC" "$NPB_BUILD"
cd "$NPB_BUILD" || exit 1
WT=wtime_ompi.c
[ -f "config/$WT" ] || WT=wtime_system.c
# (generado con echo, sin heredoc: tools/check.sh analiza los heredocs con
# nombre como scripts de shell y un make.def no lo es)
{
  echo "CC = mpicc -march=$MARCH"
  echo "MPICC = mpicc -march=$MARCH"
  echo "FC = mpiifx -march=$MARCH"
  echo "MPIFC = mpiifx -march=$MARCH"
  echo 'FLINK = $(FC)'
  echo "CCFLAGS = -O3"
  echo "FFLAGS = -O3 -march=$MARCH"
  echo "FLINKFLAGS ="
  echo "RAND = randi8"
  echo "RANDPAR = randi8"
  echo "BINDIR = ../bin"
  echo "WTIME = $WT"
} > config/make.def
mkdir -p bin "$INTELC_NPB"   # NPB enlaza desde el subdirectorio del kernel: ../bin = bin/ del build
for k in ft ep cg mg; do
  echo "== NPB intelc/$ARCH: make $k CLASS=D (mpiifx, -march=$MARCH)"
  bash "$W" make "$k" CLASS=D > "$CMDLOG_DIR/make-npb-$k-$ARCH.log" 2>&1 \
    || { echo "!! make $k CLASS=D falló con mpiifx -march=$MARCH (log: $CMDLOG_DIR/make-npb-$k-$ARCH.log); NO se prueban flags alternativos" >&2; exit 7; }
  bin="bin/$k.D.x"; [ -f "$bin" ] || bin="../bin/$k.D.x"
  [ -f "$bin" ] || { echo "!! $k.D.x no generado (ver make-npb-$k-$ARCH.log)" >&2; exit 7; }
  cp "$bin" "$INTELC_NPB/"
  echo "   ok $k.D.x"
done
cd "$TURGALIUM_SCRATCH/src/intelc" || exit 1

# ---- 4) ldd + sha256 de los NPB ---------------------------------------------
for k in ft ep cg mg; do
  B="$INTELC_NPB/$k.D.x"
  ldd "$B" > "$CMDLOG_DIR/ldd-npb-$k-$ARCH.txt" 2>&1
  grep -q 'libmpi.so.12' "$CMDLOG_DIR/ldd-npb-$k-$ARCH.txt" \
    || { echo "!! ldd $k.D.x sin libmpi.so.12 de Intel MPI (ldd-npb-$k-$ARCH.txt)" >&2; exit 4; }
  grep -q 'libintlc' "$CMDLOG_DIR/ldd-npb-$k-$ARCH.txt" \
    || { echo "!! ldd $k.D.x sin libintlc (runtime de ifx; ldd-npb-$k-$ARCH.txt)" >&2; exit 4; }
  grep -q 'libimf' "$CMDLOG_DIR/ldd-npb-$k-$ARCH.txt" \
    || { echo "!! ldd $k.D.x sin libimf (runtime de ifx; ldd-npb-$k-$ARCH.txt)" >&2; exit 4; }
  sha256sum "$B" >> "$SHAFILE"
done
echo "== ldd y sha256 de los 4 NPB correctos ($SHAFILE)"

# ---- 3) HPCG 3.1.0, solo spr, con mpiicpx -----------------------------------
if [ "$ARCH" = spr ]; then
  [ -d "$HPCG_SRC" ] || { echo "!! falta fuente HPCG: $HPCG_SRC" >&2; exit 1; }
  HPCG_BUILD="$TURGALIUM_SCRATCH/src/intelc/hpcg-3.1.0-intelc"
  rm -rf "$HPCG_BUILD"; cp -r "$HPCG_SRC" "$HPCG_BUILD"
  cd "$HPCG_BUILD" || exit 1
  unset I_MPI_CXX   # no heredar de builds anteriores: el CXX es el wrapper de Intel con SU compilador
  # (generado con echo, sin heredoc: tools/check.sh analiza los heredocs con
  # nombre como scripts de shell y un makefile no lo es)
  {
    echo 'SHELL        = /bin/sh'
    echo 'CD           = cd'
    echo 'CP           = cp'
    echo 'LN_S         = ln -s -f'
    echo 'MKDIR        = mkdir -p'
    echo 'RM           = /bin/rm -f'
    echo 'TOUCH        = touch'
    echo 'TOPdir       = .'
    echo 'SRCdir       = $(TOPdir)/src'
    echo 'INCdir       = $(TOPdir)/src'
    echo 'BINdir       = $(TOPdir)/bin'
    echo 'MPdir        ='
    echo 'MPinc        ='
    echo 'MPlib        ='
    echo 'HPCG_INCLUDES = -I$(INCdir) -I$(INCdir)/$(arch) $(MPinc)'
    echo 'HPCG_LIBS     ='
    echo 'HPCG_OPTS     = -DHPCG_NO_OPENMP'
    echo 'HPCG_DEFS     = $(HPCG_OPTS) $(HPCG_INCLUDES)'
    echo 'CXX          = mpiicpx'
    echo 'CXXFLAGS     = $(HPCG_DEFS) -O3 -march=sapphirerapids'
    echo 'LINKER       = $(CXX)'
    echo 'LINKFLAGS    = $(CXXFLAGS)'
    echo 'ARCHIVER     = ar'
    echo 'ARFLAGS      = r'
    echo 'RANLIB       = echo'
  } > setup/Make.intelc
  echo "== HPCG intelc/spr: configure + make (mpiicpx, -DHPCG_NO_OPENMP -O3 -march=sapphirerapids)"
  # El configure de HPCG termina con `cp -f $setup_file setup` (línea 50 del
  # fuente), que copia el fichero de setup sobre el DIRECTORIO `setup/` que el
  # propio configure se asegura de crear: falla SIEMPRE con «are the same
  # file» en un árbol HPCG estándar. Es el mismo error que en la fase B
  # quedaba oculto por el `| tail -2` de compile_phaseB.sbatch. El artefacto
  # real (el Makefile) se genera antes (línea 40 del configure): se tolera
  # ese fallo SOLO si el log contiene «are the same file» Y el Makefile se ha
  # generado; cualquier otro fallo del configure sigue siendo exit 7.
  if bash "$W" ./configure intelc > "$CMDLOG_DIR/configure-hpcg-intelc.log" 2>&1; then
    echo "   configure: exit 0"
  elif grep -q "are the same file" "$CMDLOG_DIR/configure-hpcg-intelc.log" && [ -f Makefile ]; then
    echo "   configure: exit != 0 TOLERADO (cp sobre sí mismo del configure de HPCG; Makefile generado)"
  else
    tail -20 "$CMDLOG_DIR/configure-hpcg-intelc.log"
    echo "!! configure HPCG falló" >&2
    exit 7
  fi
  bash "$W" make -j 8 > "$CMDLOG_DIR/make-hpcg-intelc.log" 2>&1 \
    || { tail -20 "$CMDLOG_DIR/make-hpcg-intelc.log"; echo "!! make HPCG falló" >&2; exit 7; }
  [ -f bin/xhpcg ] || { echo "!! xhpcg no generado (ver make-hpcg-intelc.log)" >&2; exit 7; }
  mkdir -p "$INTELC_HPCG"
  cp bin/xhpcg "$INTELC_HPCG/xhpcg"
  ldd "$INTELC_HPCG/xhpcg" > "$CMDLOG_DIR/ldd-hpcg-intelc.txt" 2>&1
  grep -q 'libmpi.so.12' "$CMDLOG_DIR/ldd-hpcg-intelc.txt" \
    || { echo "!! ldd xhpcg sin libmpi.so.12 de Intel MPI (ldd-hpcg-intelc.txt)" >&2; exit 5; }
  sha256sum "$INTELC_HPCG/xhpcg" >> "$SHAFILE"
  echo "   ok xhpcg (intelc)"
  cd "$TURGALIUM_SCRATCH/src/intelc" || exit 1
fi

# ---- 5) humo en el mismo job (forma de la celda 1n de la fase B, intel/mlx) --
case "$ARCH" in
  spr) RANKS=64; MAP="0-31,56-87" ;;
  clx) RANKS=32; MAP="0-15,18-33" ;;
esac
export I_MPI_FABRICS=ofi FI_PROVIDER=mlx I_MPI_DEBUG=5
export I_MPI_PIN=1 I_MPI_PIN_PROCESSOR_LIST="$MAP"
RUN=(mpirun -n "$RANKS" -ppn "$RANKS")   # Hydra de Intel MPI: -map-by no soportado (calib36)
MANIFEST="$CMDLOG_DIR/manifest-humo-$ARCH.csv"
echo "binario,ranks,exit_code,verificacion,class,size,runlog" > "$MANIFEST"
HUMO_OK=1
for k in ft ep cg mg; do
  B="$INTELC_NPB/$k.D.x"
  RD="$CMDLOG_DIR/humo-$k-$ARCH"; mkdir -p "$RD"
  echo "== humo NPB $k intelc/$ARCH: $RANKS ranks, pin $MAP, mlx $(date -Is)"
  if bash "$W" "${RUN[@]}" "$B" > "$RD/run.log" 2>&1; then ec=0; else ec=$?; fi
  v=NO-VERIFICADO
  if [ "$ec" -eq 0 ] \
     && ! grep -qE "Verification[[:space:]]*=[[:space:]]*UNSUCCESSFUL" "$RD/run.log" \
     && grep -qE "Verification[[:space:]]*=[[:space:]]*SUCCESSFUL" "$RD/run.log" \
     && grep -qE "Class[[:space:]]*=[[:space:]]*D" "$RD/run.log"; then
    v=SUCCESSFUL
  fi
  class="$(grep -m1 'Class' "$RD/run.log" 2>/dev/null | tr -s ' ' || true)"
  [ -n "$class" ] || class="sin-class"
  size="$(grep -m1 'Size' "$RD/run.log" 2>/dev/null | tr -s ' ' || true)"
  [ -n "$size" ] || size="sin-size"
  if [ "$k" = ft ] && [ "$v" = SUCCESSFUL ] && ! grep -q "Size.*2048x1024x1024" "$RD/run.log"; then
    v=CLASE-ERRONEA
  fi
  echo "$k.D.x,$RANKS,$ec,$v,$class,$size,$RD/run.log" >> "$MANIFEST"
  [ "$v" = SUCCESSFUL ] || HUMO_OK=0
  echo "   -> exit=$ec verif=$v $class $size"
done
if [ "$ARCH" = spr ]; then
  RD="$CMDLOG_DIR/humo-hpcg-$ARCH"; mkdir -p "$RD"
  echo "== humo HPCG intelc/$ARCH: $RANKS ranks, pin $MAP, mlx $(date -Is)"
  if ( cd "$RD" \
       && printf "HPCG benchmark input file\nSandia National Laboratories; University of Tennessee, Knoxville\n104 104 104\n60\n" > hpcg.dat \
       && bash "$W" "${RUN[@]}" "$INTELC_HPCG/xhpcg" > run.log 2>&1 ); then ec=0; else ec=$?; fi
  v=NO-VERIFICADO
  # exit 0 exigido también aquí (coherente con NPB); VALID por stdout o por el
  # HPCG-Benchmark_*.txt del rundir (agrupados: el txt no salta el gate de ec)
  if [ "$ec" -eq 0 ] && { grep -qE "HPCG[[:space:]]+result[[:space:]]+is[[:space:]]+VALID" "$RD/run.log" 2>/dev/null \
     || { ls "$RD"/HPCG-Benchmark_*.txt >/dev/null 2>&1 \
          && grep -q "HPCG result is VALID" "$RD"/HPCG-Benchmark_*.txt; }; }; then
    v=VALID
  fi
  echo "xhpcg,$RANKS,$ec,$v,-,-,$RD/run.log" >> "$MANIFEST"
  [ "$v" = VALID ] || HUMO_OK=0
  echo "   -> exit=$ec verif=$v"
fi
cat "$MANIFEST"
if [ "$HUMO_OK" -ne 1 ]; then
  echo "!! humo intelc con verificaciones fallidas (manifiesto: $MANIFEST)" >&2
  exit 6
fi
echo "== fin compilación + humo intelc ($ARCH, job $SLURM_JOB_ID) $(date -Is)"
echo "== binarios: $INTELC_NPB (y $INTELC_HPCG/xhpcg en spr); sha256 en $SHAFILE"
