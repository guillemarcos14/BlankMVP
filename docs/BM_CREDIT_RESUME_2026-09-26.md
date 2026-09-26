# Correcciones tras recuperar el acceso a la API

## Evidencia conservada

El 26/09/2026 se repitió la evaluación sobre `01cb98b88e6f4e7cbd2218e3769b443f1988d89e`, con fuente limpia capturada antes del primer turno y sin cambios durante la ejecución. El informe `tmp/bm-semantic/product-next-live-credit-resume-01cb98b.json` conserva 925 turnos y su SHA-256 es `ceaa4b59b4cf47ae2f00bea5d83b3233abd4c416dc408f23613d0daa5acc7a7b`. Intención, parámetros, transiciones, procedencia, decisión y acciones pasaron 925/925; hubo dos fallos del extractor, uno incompleto y un timeout. Las respuestas todavía requerían revisión independiente.

El juez v8 completó los 925 turnos: 776 excelentes, 89 aceptables, 60 deficientes, 33 hallazgos graves y **93,51% de aprobación**. Informe original: `tmp/bm-semantic/product-next-judge-credit-resume-01cb98b.json`, SHA-256 `691f271378c8c6bb67d85e9a696e9fd1a717e44f33868723e3921ad50c1b4a81`. No es una aprobación de release. Dos peticiones del juez quedaron detenidas; se conservaron sus 923 resultados y se reanudaron únicamente los pendientes. Las peticiones del juez tienen ahora timeout de 45 segundos.

Un muestreo adicional de cinco recorridos y diez turnos en español encontró dos defectos ausentes del corpus inglés: una retirada con explicación no cerraba la petición, y la conversación libre prometía aplicar un límite diario con caducidad sin emitir una acción. Inputs, respuestas y trazas originales permanecen en `tmp/bm-semantic/spanish-credit-resume-01cb98b`. Es una muestra de diagnóstico sintética, no un holdout ni una prueba de dispositivo.

El smoke completo del backend privado anterior pasó **9/9** comprobaciones y **12/12** limpiezas: `Codigo-product-release/tmp/assistant-app-cloud/full-after-credit-20260926.json`, SHA-256 `bbc771f3f2712587a1ef7f3a111eb104d01ea3b8d9c4ebcf38e3a0ddd86aec0f`. Comprueba conversación real con modelo, aislamiento de cuentas/instalaciones, reintento inmutable, estado compartido, cancelación y conservación de un recibo fallido simulado. No envía mensajes, APNs ni demuestra bloqueo físico. Ese resultado pertenece al deploy privado anterior; cualquier nuevo despliegue debe repetirlo.

## Cambios de producto

- La retirada se reconoce como una instrucción dentro del mensaje, preservando explicaciones y el orden de posteriores correcciones. Las cantidades negativas no se convierten en duraciones positivas.
- La extracción representa cantidades solicitadas fuera de rango sin deformarlas. El validador y el ejecutor conservan sus límites. El modelo puede decir «40 días»; eso sigue sin autorizar una programación de 40 días. Un reintento transitorio comparte el presupuesto total de 20 segundos y conserva sus diagnósticos.
- La respuesta distingue hechos solicitados, capacidades disponibles y ejecución verificada. Eliminar una acción no deja detrás un relato de éxito. Las condiciones, atribuciones al usuario y consejos siguen siendo conversación válida.
- Las respuestas de configuración dependen de la acción actual; no arrastran un selector antiguo cuando la selección ya existe. Los conflictos de horario y las limitaciones de fecha, duración e inicio/caducidad de límites diarios se explican sin prometer una capacidad inexistente.
- Repetir «sí» o «listo» debe reutilizar la propuesta ya transportada. Un selector que lleva un plan incorporado ya puede aplicarlo al aceptarse; la posterior disponibilidad de selección no autoriza otra ejecución. Las nuevas instrucciones explícitas conservan su propio ciclo.

## Corrección versionada de las expectativas

`tools/datasets/bm_product_journeys_v1.json` permanece byte a byte intacto. La revisión independiente encontró que algunos ejemplos esperaban precisamente los duplicados que el producto debía evitar.

`tools/build_bm_product_journeys_v2.js` lee exclusivamente ese archivo con SHA fijado. No importa el runtime, resultados del modelo ni el juez. Produce `bm_product_journeys_v2.json` y un manifiesto con cada cambio justificado: **85 expectativas de acciones pasan a lista vacía**, manteniendo los 925 inputs, contextos, estados y decisiones. Son 45 correcciones en las cinco variantes de nueve pasos de configuración y 40 continuaciones de edición con selector. Se conservan 40 recorridos base × 5 continuaciones; no se presenta como 200 problemas independientes ni como una muestra nueva de usuarios.

La revisión cruzada descartó una deduplicación basada solo en la última fase: sustituir un plan transportado por un nuevo permiso podía perder el plan pendiente o duplicar uno que el iPhone ya estuviera aplicando. Una propuesta ejecutable ya preparada conserva su identidad durante el flujo completo. El preflight del iPhone solicita permiso y selección desde esa misma propuesta; un simple «listo» no la sustituye por otra. El flujo que comienza exclusivamente con permiso sí puede avanzar después a una propuesta ejecutable, porque todavía no había ninguna.

El juez v9 explicita un contrato nativo que v8 omitía: presencia → permiso de Screen Time → selección. Si faltan permiso y selección, pedir permiso primero es correcto. También recibe el indicador de revisión previa y la decisión de cada turno. Sus umbrales y la prohibición de afirmar éxito sin recibo no cambian. Estos ajustes no recalifican el informe v8 ni eliminan los defectos reales que motivaron las correcciones.

## Validación del siguiente candidato

Congelar un commit limpio antes del nuevo replay; repetir los 925 turnos v2, el juez independiente y los diez turnos españoles. Ejecutar el harness con el baseline `tmp/product-harness/baseline-credit-resume-20260926.json` y `--enforce-scope`. Integrar en la rama Backend Cloud antes de publicar únicamente en staging y repetir las nueve comprobaciones cloud. Registrar los resultados finales y sus hashes sin sustituir los informes anteriores.

La distribución firmada y las 20 comprobaciones físicas del iPhone siguen siendo requisitos separados. Una respuesta del modelo, un mock de recibo o una captura del simulador no los sustituyen.
