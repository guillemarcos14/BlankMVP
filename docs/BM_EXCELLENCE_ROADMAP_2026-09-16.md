# Hoja de ruta operativa de excelencia de BM

**Ventana:** miércoles 16 → domingo 20 de septiembre de 2026  
**Objetivo:** llevar BM a producción con calidad cercana a la excelencia tanto en conversación como en ejecución real de planes y bloqueos desde WhatsApp hacia Blankmind.  
**Modelo de BM:** GPT-5.6 Luna.  
**Juez conversacional independiente:** GPT-5.6 Sol con razonamiento `low`.  
**Modelo excluido:** Astra.

## 1. Qué significa “cercano a la excelencia”

El objetivo del domingo no es afirmar que BM conoce todos los casos posibles. Es alcanzar una candidata de producción fiable dentro de un perímetro medido, con mecanismos para detectar y corregir rápidamente los casos nuevos.

La release solo puede considerarse preparada cuando cumple simultáneamente:

- Cero acciones incorrectas, duplicadas, prematuras o declaradas como ejecutadas sin evidencia.
- Confirmar un plan siempre termina en uno de tres estados explícitos: bloqueo verificado, configuración nativa necesaria o error identificable y recuperable.
- `20/20` recorridos físicos críticos pasan desde WhatsApp hasta el estado real del iPhone.
- `200/200` conversaciones del corpus de release no contienen fallos semánticos graves.
- Al menos `95 %` de las respuestas evaluadas alcanza el umbral conversacional definido, sin que una media pueda compensar un fallo duro.
- Ningún usuario correctamente vinculado recibe un enlace de instalación o un enlace de revisión innecesario.
- Los fallos nuevos pueden reproducirse mediante `trace_id`/`run_id` y se convierten en regresiones permanentes.

“Cercano a la excelencia” describe el comportamiento demostrado por esta evidencia. No equivale a cobertura universal ni sustituye la monitorización posterior.

## 2. Arquitectura de evaluación

### 2.1 Quién decide

| Capa | Responsable | Decide sobre | Puede aprobar por sí sola |
| --- | --- | --- | --- |
| Oracle determinista | Suite BM | Intención, slots, horarios, apps, recurrencia, confirmación, acciones y transiciones | Sí, para exactitud estructural |
| Verificación nativa | App + estado real del dispositivo | Si el bloqueo se inició, sigue activo o falló | Sí, para ejecución física |
| Juez independiente | GPT-5.6 Sol Low | Comprensión, continuidad, utilidad, naturalidad, concisión y contradicciones visibles | No, complementa al oracle |
| Revisión manual | Guillem o revisor designado | Calidad de producto, marca y casos críticos/disputados | Sí, como adjudicación explícita |
| Resultados reales | Activaciones y outcomes | Si el comportamiento ayudó y se ejecutó correctamente | Sí, como evidencia operativa posterior |

Luna nunca aprueba sus propias respuestas. Sol no puede autorizar acciones ni corregir un fallo duro mediante una puntuación alta. Guillem conserva la decisión final de gusto y producto, pero revisa una muestra acotada en lugar de todo el corpus.

### 2.2 Reglas de aprobación

Un caso falla automáticamente si ocurre cualquiera de estas condiciones:

- La acción, aplicación, duración, horario o recurrencia no coincide con lo pedido.
- BM actúa antes de tener los campos obligatorios o antes de la confirmación correspondiente.
- BM afirma que algo se ha aplicado sin verificación positiva del dispositivo.
- Se pierde o reutiliza indebidamente una confirmación anterior.
- La conversación y el payload de acción se contradicen.
- Una respuesta visible queda sin evaluación independiente cuando el oracle no puede verificar su significado.

Los resultados `failed` y `unverified` bloquean release. Las métricas blandas se informan por separado y nunca compensan estos fallos.

### 2.3 Cuándo entra la revisión humana

La revisión manual se limita a:

1. Casos de seguridad, ejecución o privacidad.
2. Desacuerdos entre oracle y juez Sol.
3. Respuestas marcadas como `unverified`.
4. Los 30 casos de mayor impacto de la candidata del sábado.
5. Regresiones físicas reales que no estén cubiertas por el corpus.

Cada adjudicación debe guardar respuesta, expectativa, hashes, veredicto, responsable y motivo. Si cambia la respuesta o la expectativa, la revisión deja de ser válida.

## 3. Contrato agéntico no negociable

La conversación puede ser flexible, pero la ejecución debe ser determinista.

Antes de crear una acción BM debe resolver:

- `apps`: apps exactas o modo guardado.
- `action`: bloqueo estricto o límite diario.
- `start`: ahora u hora concreta.
- `end`: duración, hora final o indefinido permitido.
- `recurrence`: una vez o días concretos.

Si falta un campo, BM hace una sola pregunta natural y devuelve cero acciones. Con el contrato completo, el ciclo obligatorio es:

```text
understand → propose → conversational_confirmed → queued
→ delivered_to_app → native_confirmed → execution_started
→ verified | failed | dismissed
```

Reglas:

- La confirmación conversacional congela la propuesta; no ejecuta el bloqueo.
- La confirmación nativa autoriza la ejecución en el dispositivo.
- Solo `verified` permite comunicar éxito.
- Una acción pendiente sobrevive a cierre/reapertura y vuelve a entregarse de forma idempotente.
- Repetir un mensaje no duplica la acción ni hereda confirmaciones de otra propuesta.
- La app es la autoridad de permisos, selección de apps y estado real.
- Si la app no puede recuperar o ejecutar la acción, BM muestra un error explícito y accionable.

## 4. Regla de instalación y vinculación

BM no pregunta preventivamente si Blankmind está instalada y no envía el enlace de instalación en cada propuesta.

Orden correcto:

1. BM crea y encola la acción para la identidad vinculada.
2. La app intenta recuperar la acción por instalación o teléfono.
3. Si la entrega o ejecución no puede completarse, se clasifica el motivo.
4. Solo una ausencia real de instalación/vinculación puede generar una instrucción de instalación o conexión.

Un heartbeat antiguo no demuestra que la aplicación falte. WhatsApp no debe enviar plantillas, enlaces de revisión ni URLs cuando la acción puede recuperarse desde la app.

## 5. Plan de ejecución diario

### Miércoles 16 — Diagnóstico y corrección base

**Resultado del día:** el trayecto completo está trazado, los fallos actuales son reproducibles y las acciones confirmadas ya no se pierden.

Trabajo:

1. Trazar WhatsApp/Twilio o Meta → backend → memoria/identidad → bandeja de acciones → app → permisos → bloqueo → verificación.
2. Añadir `run_id`, `trace_id`, fingerprint de propuesta y estado de lifecycle sin guardar contenido privado innecesario.
3. Reproducir los fallos actuales: acción perdida al confirmar, enlaces duplicados, falsas descargas, confirmación heredada y respuesta sin ejecución.
4. Corregir primero las invariantes de estado, transporte e identidad; después ajustar el texto.
5. Convertir cada fallo confirmado en un test de regresión antes de desplegar.

Gate de salida:

- Todos los fallos conocidos tienen prueba reproducible.
- Cero acciones se pierden entre confirmación conversacional y recuperación en la app.
- Los usuarios vinculados no reciben enlaces de instalación.
- Oracle, tests de canal y product harness pasan.

### Jueves 17 — Ejecución fiable y recuperación

**Resultado del día:** cada plan confirmado progresa de forma idempotente hasta un desenlace observable.

Trabajo:

1. Completar y persistir los estados `queued → delivered → confirmed → execution_started → verified|failed|dismissed`.
2. Recuperar acciones después de cerrar/reabrir Blankmind o volver a primer plano.
3. Continuar el flujo tras conceder permisos o seleccionar aplicaciones, sin obligar al usuario a reconstruir el plan.
4. Probar bloqueo inmediato, franja horaria, límite diario, recurrencia y modo guardado.
5. Probar duplicados, reintentos, expiración, desconexión, permisos denegados y dos confirmaciones consecutivas.

Gate de salida:

- Repetir un evento es seguro y no crea dobles bloqueos.
- La acción pendiente conserva exactamente apps, duración, horario y recurrencia.
- Todo fallo termina en un estado explícito, no en silencio.
- La app solo informa `verified` con evidencia positiva.

### Viernes 18 — Build física y evaluación amplia

**Resultado del día:** una build distribuida demuestra el flujo real y el corpus de release queda evaluado.

Trabajo:

1. Compilar, archivar, distribuir e instalar la build candidata; distinguir build local, firma, subida y disponibilidad real.
2. Ejecutar 20 pruebas físicas desde WhatsApp, incluyendo reapertura, permisos, selección exacta, cancelación, fallo y reintento.
3. Evaluar al menos 200 conversaciones únicas o mutaciones independientes con oracle y GPT-5.6 Sol Low.
4. Separar fallos duros, casos no verificados y defectos conversacionales.
5. Corregir todos los fallos duros y los problemas conversacionales de mayor impacto; añadir regresión por cada reparación.

Gate de salida:

- `20/20` pruebas físicas críticas pasan.
- `200/200` casos sin fallo semántico grave ni acción prematura.
- Juez Sol ≥ `95 %` y cero contradicciones duras.
- No queda ningún caso `unverified` sin adjudicación.

### Sábado 19 — Candidata de producción

**Resultado del día:** existe una candidata controlada, repetible y revisada con comportamiento equivalente en local y producción.

Trabajo:

1. Repetir corpus, mutaciones, concurrencia, idempotencia y pruebas físicas sobre el commit exacto candidato.
2. Revisar manualmente los 30 casos de mayor riesgo/impacto.
3. Desplegar la candidata mediante el proceso de release, nunca desde una rama de implementación incompleta.
4. Evaluar el endpoint desplegado con el mismo contrato y juez independiente.
5. Reparar y volver a ejecutar el gate completo ante cualquier regresión.

Gate de salida:

- Commit, dataset, expectativas, build y deploy están identificados.
- Local y producción pasan los mismos invariantes.
- No hay cambios sin evaluar después del último gate.
- Existe rollback conocido y trazabilidad suficiente para diagnosticar un caso real.

### Domingo 20 — Release y estabilización

**Resultado del día:** BM queda publicado, verificado desde WhatsApp/iPhone y monitorizado.

Trabajo:

1. Ejecutar el gate final sobre el artefacto exacto que se publicará.
2. Desplegar antes del mediodía solo si se cumplen todas las condiciones de release.
3. Repetir una prueba directa WhatsApp → Blankmind → bloqueo real → verificación.
4. Vigilar acciones reales, duplicados, expiraciones, fallos de entrega y afirmaciones no verificadas.
5. Ante un fallo duro, detener rollout o revertir; corregir, añadir regresión y repetir el gate completo.

Gate de salida:

- Producción cumple todos los criterios de la sección 1.
- La prueba final registra bloqueo real y desenlace verificable.
- No quedan errores críticos abiertos ni diferencias sin explicar entre conversación y ejecución.

## 6. Matriz mínima de pruebas físicas (20 casos)

La batería debe cubrir, al menos:

| Grupo | Casos |
| --- | ---: |
| Bloqueo inmediato: una app, varias apps, modo guardado | 4 |
| Programación: ventana, duración, recurrencia, corrección previa | 4 |
| Límite diario: creación, edición, dato faltante | 3 |
| Estado de app: abierta, cerrada, reapertura, segundo plano | 3 |
| Permisos/selección: concedidos, denegados, selección pendiente | 3 |
| Robustez: duplicado, cancelación, fallo recuperable | 3 |

Cada prueba guarda: prompt, turnos, acción esperada, lifecycle observado, estado real del iPhone, resultado y evidencia. Una respuesta correcta con bloqueo incorrecto falla; un bloqueo correcto acompañado de una afirmación falsa también falla.

## 7. Sistema de mejora continua

Cada incidencia real sigue este ciclo:

```text
capturar → anonimizar → reproducir → clasificar → fijar expectativa
→ reparar → añadir regresión → evaluar independiente → desplegar
→ verificar outcome real
```

Prioridad de reparación:

1. Seguridad, privacidad o ejecución incorrecta.
2. Acción perdida, duplicada o falsamente confirmada.
3. Interpretación semántica errónea.
4. Contexto, continuidad o recuperación deficientes.
5. Naturalidad, concisión y tono.

BM no mejora modificando pesos del modelo en esta fase. Mejora mediante contratos, estado, prompts, routing, memoria acotada, gates, outcomes reales y regresiones. El fine-tuning solo se considerará cuando exista volumen real, etiquetado consistente y un error repetido que estas capas no resuelvan mejor.

## 8. Comandos de validación

Desde `Extra/Codigo` y después de crear una baseline específica antes de editar:

```powershell
node tools/bm_semantic_oracle_test.js --out tmp/bm-semantic/oracle-mutations.json
node tools/bm_excellence_gate.js
node tools/bai_release_gate.js --save --count 200 --quality-judge
node tools/product_harness.js --contract tools/product_harness_contract.json --baseline tmp/product-harness/<baseline>.json --mode validate --enforce-scope
```

Para evaluar el endpoint desplegado:

```powershell
node tools/bai_release_gate.js --save --count 200 --production --quality-judge
```

Las suites masivas deben llamar al planner, nunca a webhooks de WhatsApp/SMS que envíen mensajes reales. Los smoke tests de proveedor y dispositivo se ejecutan aparte y con volumen controlado.

## 9. Reglas para futuras conversaciones de Codex

Toda conversación que implemente una parte de esta hoja de ruta debe:

1. Leer `Blank Brain` y los documentos `BM_EVALUATION.md`, `BM_EXCELLENCE_ARCHITECTURE.md` y este archivo.
2. Crear una baseline del product harness antes de editar.
3. Declarar un único resultado concreto y no mezclar implementación, release y experimentos no relacionados.
4. Convertir cualquier fallo nuevo en prueba permanente antes de corregirlo.
5. No declarar éxito basándose solo en texto, tests unitarios o una build; aportar evidencia de la capa afectada.
6. Usar GPT-5.6 Sol Low para juzgar conversación y el oracle/app para exactitud y ejecución.
7. No usar Astra.
8. No actualizar expectativas para hacer pasar una implementación incorrecta.
9. No desplegar si queda un fallo duro, un caso `unverified`, una revisión inválida o una prueba física requerida pendiente.
10. Cerrar con commit/deploy/build exactos, resultados de gates, límites conocidos y siguiente verificación física.

### Prompt breve reutilizable

```text
Continúa la hoja de ruta de excelencia de BM definida en
docs/BM_EXCELLENCE_ROADMAP_2026-09-16.md.

Trabaja únicamente en: <resultado concreto>.
Lee primero Blank Brain y los documentos BM enlazados. Crea la baseline
del product harness antes de editar. Usa GPT-5.6 Sol Low como juez
conversacional independiente y no uses Astra. Añade una regresión por
cada fallo corregido. No declares una acción ejecutada sin verificación
nativa y no despliegues mientras exista un fallo duro o no verificado.

Entrega: cambio implementado, tests/gates, commit exacto, estado de deploy
y la prueba física pendiente o completada.
```

## 10. Fuentes operativas relacionadas

- `docs/BM_EVALUATION.md`: responsabilidades del oracle, Sol Low, replay y criterios semánticos.
- `docs/BM_EXCELLENCE_ARCHITECTURE.md`: contratos, loop, verificación, observabilidad y seguridad.
- `docs/BM_PRODUCTION_EVALUATION.md`: evaluación del endpoint desplegado.
- `docs/BM_CHANNEL_AUDIT.md`: transporte y riesgos por canal.
- `docs/BAI_TRAINING_PLAN.md`: sistema de mejora y aprendizaje operativo.
- `Blank Brain/PROCESOS/desarrollo.md`: proceso de desarrollo y gates obligatorios.
