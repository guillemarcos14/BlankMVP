# Correcciones tras recuperar el acceso a la API

## Evidencia conservada

El 26/09/2026 se repitió la evaluación sobre `01cb98b88e6f4e7cbd2218e3769b443f1988d89e`, con fuente limpia capturada antes del primer turno y sin cambios durante la ejecución. El informe `tmp/bm-semantic/product-next-live-credit-resume-01cb98b.json` conserva 925 turnos y su SHA-256 es `ceaa4b59b4cf47ae2f00bea5d83b3233abd4c416dc408f23613d0daa5acc7a7b`. Intención, parámetros, transiciones, procedencia, decisión y acciones pasaron 925/925; hubo dos fallos del extractor, uno incompleto y un timeout. Las respuestas todavía requerían revisión independiente.

El juez v8 completó los 925 turnos: 776 excelentes, 89 aceptables, 60 deficientes, 33 hallazgos graves y **93,51% de aprobación**. Informe original: `tmp/bm-semantic/product-next-judge-credit-resume-01cb98b.json`, SHA-256 `691f271378c8c6bb67d85e9a696e9fd1a717e44f33868723e3921ad50c1b4a81`. No es una aprobación de release. Dos peticiones del juez quedaron detenidas; se conservaron sus 923 resultados y se reanudaron únicamente los pendientes. Las peticiones del juez tienen ahora timeout de 45 segundos.

Un muestreo adicional de cinco recorridos y diez turnos en español encontró dos defectos ausentes del corpus inglés: una retirada con explicación no cerraba la petición, y la conversación libre prometía aplicar un límite diario con caducidad sin emitir una acción. Inputs, respuestas y trazas originales permanecen en `tmp/bm-semantic/spanish-credit-resume-01cb98b`. Es una muestra de diagnóstico sintética, no un holdout ni una prueba de dispositivo.

El smoke completo del backend privado anterior pasó **9/9** comprobaciones y **12/12** limpiezas: `Codigo-product-release/tmp/assistant-app-cloud/full-after-credit-20260926.json`, SHA-256 `bbc771f3f2712587a1ef7f3a111eb104d01ea3b8d9c4ebcf38e3a0ddd86aec0f`. Comprueba el flujo cloud real de conversación, aislamiento de cuentas/instalaciones, reintento inmutable, estado compartido, cancelación y conservación de un recibo fallido simulado. No registra la procedencia de cada respuesta: por sí solo no acredita inferencia activa. No envía mensajes, APNs ni demuestra bloqueo físico. Ese resultado pertenece al deploy privado anterior; cualquier nuevo despliegue debe repetirlo.

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

## Validación y límite encontrado

El candidato `e47484b0ad2c036aa6d3dfcbed5225dcfc6826d4` pasó el harness **62/62**, incluido el nuevo control de entrega semántica. Su repetición con API terminó el 26/09 a las 15:38 UTC: 925 turnos, **cero turnos de modelo activos** y 925 fallos de proveedor correctamente marcados como fallo de seguridad del evaluador, aunque el fallback conserve las acciones esperadas. El informe `tmp/bm-semantic/product-next-live-v2-e47484b.json` no aprueba calidad; SHA-256 `18cb5c957a46ea1937b11606617ce56c258a06ccd30d047ab65b993cbec27e5e`. La fuente estaba limpia e inalterada. No se ejecutó un juez sobre respuestas que pretendieran pasar por generación real.

La repetición española capturó diez respuestas HTTP 429 del proveedor: `insufficient_quota`, `credit_balance_exhausted`. Se usó la variable `OPENAI_API_KEY` heredada, sin sustituirla ni cargar otro `.env`. Eso demuestra el rechazo de la credencial disponible, no el saldo de todas las cuentas o proyectos de Guillem. Se conservaron las respuestas originales y los criterios previos en `tmp/bm-semantic/spanish-credit-resume-e47484b`. El fallback pasó nueve de diez criterios; el último era repetir el aviso de cancelación después de «Gracias».

Ese detalle se corrigió en `a6f9e501165979b7ef81377cd32ea23aaa023c5d`: agradecer tras cancelar responde «De nada» / «You're welcome» y mantiene la cancelación, los slots vacíos y ninguna acción. Un agradecimiento dentro de otra instrucción no elimina el aviso ni modifica su autorización. Pruebas semánticas **105/105** y de entrega **26/26**. Harness final **62/62**, baseline de reanudación y `--enforce-scope`, run `ph_1790437280056_9841776d`.

El replay final `tmp/bm-semantic/product-next-final-a6f9e50.json`, SHA-256 `a96a811f46e8cd8c2137b0b41233338e9d41ecb5746b38e7472fff0f743e46e1`, captura ese commit limpio antes de empezar y confirma que no cambia: **925/925 en cada una de siete dimensiones deterministas**, cero modelo activo, 925 textos aún `unverified`. Su salida 1 conserva correctamente el gate incompleto. Los diez turnos españoles repetidos sin red satisfacen sus diez criterios; tampoco son una aprobación del modelo.

El contrato v2 no se ha ajustado para resolver el fallo de cuota. Los 85 cambios de acciones se hicieron antes de esta evaluación y tienen el manifiesto y la revisión independientes descritos arriba. Se preservan íntegros todos los resultados anteriores.

## Recuperación sin repetir trabajo válido

Antes de otra batería con modelo, comprobar una sola petición real con la credencial del entorno. Si devuelve cuota agotada, conservar el diagnóstico y detenerse. Con proveedor operativo: congelar fuente limpia, repetir v2 con `--model`, exigir 925 turnos activos sin fallos funcionales y ejecutar el juez con `--limit 925 --concurrency 8`; sus checkpoints permiten reanudar únicamente las revisiones pendientes, sin regenerar respuestas para encajar con un hash aprobado. Mantener separados los resultados del modelo, el transporte cloud y el dispositivo.

La marca de propuesta preparada es deduplicación, no acuse de entrega. Una carrera en la que una nueva versión de memoria invalida un encolado antiguo falla sin ejecutar; la persona puede recuperar el resultado desde Blankmind o emitir una nueva instrucción explícita. Una respuesta breve por sí sola no puede rearmar ni prolongar la petición anterior.

## Backend integrado y representación nativa

Runtime final `a6f9e50`, integrado como `77a01e050e0c1d9c6fce514a12644928976cc93b`, subido y validado **62/62** con el baseline previo y scope (`ph_1790437338412_a6913d9b`). Deploy privado `6ab7e819cbfca0f727997215`: cuatro funciones, cuatro digests remotos comprobados, acceso anónimo HTTP 401, base aislada y sin proveedores salientes ni cron. Smoke actual `infrastructure-77a01e050e0c-20260926-154353.json`: **4/4**, **12/12 limpiezas**, run `bdd53442-9371-496e-8d24-ad56785b0b89`. No se modificaron migraciones ni producción.

La única preflight remota del modelo conservada sobre la integración inmediatamente anterior (`588ddc1`) devuelve `semantic_model_http_429` y fallback; el endpoint no expone el subtipo del error del proveedor. El subtipo de saldo agotado sí está demostrado en el diagnóstico local. Las nueve pruebas cloud reales de las 15:00 UTC permanecen como evidencia de aquel despliegue anterior, no del final. No se repitieron llamadas con modelo tras confirmar el rechazo.

CI [iOS a6f9e50](https://github.com/guillemarcos14/BlankmindAI/actions/runs/36252850746) terminó correctamente: build de simulador sin firma, pruebas nativas y 648 casos app/extensión, más ocho capturas SwiftUI del runtime final revisadas. La revisión confirma disposición y legibilidad, incluidas las capturas con tamaño máximo; no certifica gestos, VoiceOver ni ejecución física. CI [BM a6f9e50](https://github.com/guillemarcos14/BlankmindAI/actions/runs/36252850729) pasó harness/scope 62/62, PostgreSQL 15 real y compilación/tests Android. Metadatos, logs y hashes de capturas se conservan en `tmp/ci-a6f9e50`.

La distribución firmada y las 20 comprobaciones físicas del iPhone siguen siendo requisitos separados. Una respuesta del modelo, un mock de recibo o una captura del simulador no los sustituyen.
