# Reglas de decisión a priori

Este documento fija todas las decisiones condicionales del diseño experimental. Debe estar commiteado **antes del primer run**; la fecha del commit es la prueba de que las reglas no se ajustaron a los datos.

Las reglas no se modifican a posteriori. Si una regla resulta inadecuada, se sigue aplicando tal como está escrita, y la inadecuación se documenta en `rules/DEVIATIONS.md` y se discute en el artículo. Cualquier situación no cubierta por estas reglas se documenta en `rules/DEVIATIONS.md` antes de actuar.

---

## R1. Distinguibilidad entre configuraciones

Dos configuraciones son **distinguibles** si y solo si se cumplen ambas condiciones:

- la diferencia relativa entre sus medianas supera el **5 %**, y
- sus rangos intercuartílicos (IQR) **no se solapan**.

El primer run de cada celda se descarta como calentamiento y no cuenta para ningún estadístico. Esta regla se usa en todas las demás que hablan de "distinguible".

## R2. Selección de pares stack-transporte tras la fase A

1. Para cada par stack-transporte se calcula una puntuación a partir de OSU: posición media en el ranking de latencia (mensaje pequeño, 8 B) y de ancho de banda (mensaje grande, 4 MiB) en pt2pt, y de allreduce y alltoall a 8 nodos (mensaje de 64 KiB).
2. Pasan a la fase B los **3 pares con mejor puntuación**, sin considerar el stack.
3. Pasa además el **peor par no-tcp**, definido como el de peor puntuación entre todos los pares no-tcp probados en la fase A, sumando ambos stacks.
4. Si el peor par no-tcp ya está entre los 3 mejores, la fase B se queda con esos 3 pares. La fase B tiene, por tanto, **un máximo de 4 pares** en cualquier caso.
5. Que los 3 mejores pertenezcan al mismo stack es aceptable e intencionado: la fase B compara transportes; el contraste entre stacks lo cubren la fase A, las anclas y la prueba de infrautilización.

## R3. Sobrecarga de la instrumentación de nivel 1

1. Se mide **durante la calibración, antes de la fase A**, en ambos stacks, con una celda de referencia (FT, 8 nodos, un transporte no-tcp disponible en cada stack), con y sin instrumentación de nivel 1. La clase de FT es la que fije R8; por eso, dentro de la calibración, los runs de R8 se ejecutan antes que la medición de sobrecarga. El intervalo base de muestreo de frecuencia y energía es de **1 s**.
2. Si la sobrecarga es **≤ 2 %** en ambos stacks, el nivel 1 completo se aplica a todos los runs.
3. Si supera el 2 % en algún stack, se recorta en este orden, volviendo a medir tras cada paso, hasta quedar por debajo del umbral:
   a. mpiP sale de la matriz y se aplica solo en **una repetición dedicada adicional** por celda;
   b. el muestreo de frecuencia y energía pasa de 1 s a 5 s;
   c. el muestreo de frecuencia y energía se sustituye por lecturas al inicio y al final del run.
4. El mismo nivel de instrumentación se aplica a ambos stacks, aunque solo uno supere el umbral.
5. La sobrecarga medida y el nivel aplicado se reportan en el artículo.

## R4. Configuración CMMSE de las anclas

La celda ancla replica la configuración del CMMSE en:

- versiones de HPL y HPCG;
- parámetros de entrada: N, NB y P×Q en HPL; tamaño de problema local en HPCG;
- número de nodos y ranks por nodo;
- binding, si quedó registrado;
- nodos concretos, si se pueden identificar en los registros del CMMSE y están disponibles.

Cualquier elemento que no pueda igualarse se lista en una tabla de desviaciones respecto al CMMSE, que se publica junto a los resultados. Si el número de nodos del CMMSE es mayor de 8, la ancla se ejecuta a 8 nodos y se declara como desviación.

## R5. Desdoblamiento de las anclas según el stack del CMMSE

1. El descubrimiento compara las versiones de compilador, MPI, UCX y libfabric disponibles con las usadas en el CMMSE, reconstruidas a partir del repositorio, los scripts de lanzamiento y las cabeceras de salida de los benchmarks.
2. Si el stack del CMMSE sigue disponible (módulos instalados o reproducible en contenedor sin compilar el MPI), cada ancla se ejecuta **dos veces**: con el stack del CMMSE y con el stack actual.
3. Si no está disponible, cada ancla se ejecuta solo con el stack actual y la comparación con el CMMSE se declara como **cambio conjunto de sistema y software**, sin atribución.
4. Si las versiones del CMMSE no pueden reconstruirse, se declara y se aplica el punto 3.

## R6. Entrada de HPL fuera de las anclas

HPL se ejecuta en la matriz de la fase B **solo si**, en HPCG a 8 nodos, las dos mejores configuraciones **no son distinguibles** (R1). En ese caso, HPL se ejecuta con esas dos configuraciones, a 8 nodos, 6 repeticiones. En caso contrario no se ejecuta, y el artículo lo declara.

## R7. Entrada al nivel 2 de instrumentación

Una celda se repite con instrumentación de nivel 2 si se cumple alguna de estas condiciones y los datos de nivel 1 (transporte efectivo, contadores IB, frecuencias, afinidad, fingerprint) **no la explican**:

- dos configuraciones son distinguibles (R1) sin causa identificable;
- el ranking de transportes de la fase B contradice el de la fase A;
- hay discrepancias de afinidad sistemáticas (R10).

Nunca se aplica nivel 2 a la matriz completa. Cada celda que entra en nivel 2 se registra con el motivo.

## R8. Clase de NPB

1. Se elige la **menor clase** en la que, en la calibración, el kernel FT cumple:
   - duración **≥ 30 s** en el tamaño máximo de la matriz de esa partición, y
   - cabe en la memoria de **un nodo** en el tamaño mínimo.
2. La misma clase se aplica a todos los kernels de esa partición.
3. En cpu112c se espera clase D. Si ninguna clase cumple ambas condiciones, se usa la que cumple la condición de duración y el nivel de 1 nodo se elimina de la matriz, declarándolo.
4. En los casos ligeros la regla se aplica por partición o clúster.

## R9. Kernel del protocolo ligero

El kernel de NPB usado en los casos ligeros es el que, en cpu112c a 8 nodos, presenta **mayor dispersión relativa entre transportes** (rango de medianas entre los pares seleccionados, dividido por la mediana del mejor). EP queda excluido por ser el control.

## R10. Discrepancias de afinidad

1. Cada run registra el mapa de afinidad pedido y el real, y una etiqueta de coincidencia.
2. **Ningún run se descarta** por discrepancia de afinidad.
3. Las discrepancias se cuentan por stack, partición y tamaño de job. Si afectan a más del 10 % de los runs de una combinación, se consideran **sistemáticas** y se analizan como hallazgo.
4. Si excluir los runs discrepantes cambia alguna conclusión (según R1), se reportan ambos resultados; si no, se declara en una frase.

## R11. Efecto día en las anclas

1. Las repeticiones de cada ancla se reparten entre dos reservas en días distintos (la mitad en cada una; HPL: 3 + 3).
2. Se aplica R1 entre las medianas de cada día.
3. Si los días son **distinguibles**, se reportan por separado y el efecto día se discute como hallazgo de variabilidad temporal.
4. Si no lo son, se agregan.
5. En las anclas HPL, con n = 5 efectivas (2 o 3 por día), el criterio es conservador y así se declara. Lo mismo aplica al protocolo ligero (5 repeticiones, 4 efectivas).

## R12. Estabilidad de cpu48c

cpu48c pasa del descubrimiento al protocolo ligero **solo si**, en la ventana formada por las 24 h previas al job de descubrimiento más la duración del job:

- ningún nodo de la partición ha estado drenado, caído o en fallo según Slurm, y
- no hay errores del cliente Lustre en el log del kernel (desalojos, pérdidas de conexión con MDS/OST, timeouts de RPC) en ningún nodo.

Si no se cumple, cpu48c se caracteriza únicamente en la fase de descubrimiento y el artículo explica por qué.

**Fuentes del historial de estados de nodo**, por orden de preferencia:

1. eventos de nodo registrados en la contabilidad de Slurm (`sacctmgr show event`), si son accesibles;
2. historial facilitado por los administradores del sistema;
3. si ninguno está disponible, la ventana se reduce a la duración del job de descubrimiento: estado actual de los nodos al inicio y al final del job y log del kernel leído desde el propio job. Se declara que la comprobación de las 24 h previas no fue posible.

La fuente utilizada queda registrada.

## R13. Exceso del presupuesto de máquina

Si la calibración indica que las fases A y B de cpu112c superan las **24 h de máquina**, se recorta en este orden hasta caber:

1. repeticiones de NPB de 10 a 5;
2. repeticiones de HPCG en la matriz de 10 a 5;
3. HPCG en la matriz solo a 8 nodos;
4. se eliminan los kernels CG/MG (quedan EP y FT);
5. se elimina el nivel de 1 nodo en NPB;
6. repeticiones de OSU de 10 a 5.

El número de pares de la fase B (máximo 4, R2) no se recorta, porque el peor par no-tcp es necesario para contrastar la hipótesis sobre OSU. Las anclas (HPCG y HPL) y la prueba de infrautilización tampoco se recortan.

## R14. Disponibilidad de herramientas y privilegios

1. Antes del primer run se comprueba qué herramientas del nivel 1 requieren privilegios (`turbostat`, RAPL, `perfquery`).
2. Si no hay privilegios disponibles, se usa el modo sin privilegios: contadores IB en `/sys/class/infiniband/*/ports/*/counters`, frecuencias en `/sys/devices/system/cpu/*/cpufreq`, y energía declarada no disponible.
3. Si el transporte efectivo no es observable en algún stack, se declara.
4. Si un benchmark no está disponible como módulo, se compila desde su fuente oficial con el stack correspondiente y la compilación queda registrada. Esto incluye BabelStream en GPU.
5. Si no hay MPI CUDA-aware instalado, OSU en GPU se omite y se declara.
6. El modo elegido queda registrado y se aplica igual a todas las celdas de la misma partición.

## R15. Análisis de sensibilidad de los umbrales

1. Las conclusiones principales se obtienen con los umbrales fijados en estas reglas.
2. En el material suplementario se reaplican las reglas con umbrales alternativos, sin ejecutar runs adicionales:
   - R1 (distinguibilidad): 3 % y 10 %, además del 5 % nominal;
   - R10 (discrepancias sistemáticas de afinidad): 5 % y 20 %, además del 10 % nominal.
3. Para cada umbral alternativo se reporta si cambia alguna conclusión: la selección de pares de R2, la entrada de HPL (R6), la elección del kernel del protocolo ligero (R9), la atribución del antes/después y el veredicto sobre la hipótesis de OSU.
4. Si alguna conclusión cambia, se discute en el artículo como sensibilidad de ese resultado. Las decisiones ya tomadas durante la ejecución con los umbrales nominales no se rehacen.
5. El umbral de sobrecarga de R3 (2 %) no entra en este análisis: su efecto se cubre reportando la sobrecarga medida.
