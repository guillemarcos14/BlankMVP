# BM: auditoría de canales y frontera nativa

Fecha: 2026-09-15. Base inspeccionada: `a222a4a`, rama de trabajo `codex/bm-semantic-audit`. Evidencia local; no se desplegó ni se enviaron mensajes a usuarios. Los nombres de funciones permiten revisar la base aunque cambien los números de línea.

## Hallazgos principales

### 1. El modelo configurado no demuestra el modelo usado

`blanked-agent.js:modelPlan` y `modelConversationPlan` llaman a `/v1/responses` con `process.env.OPENAI_MODEL || "gpt-5.6-luna"`. En la base, `.env.membership.example` recomendaba `gpt-4.1-mini`; esta rama lo corrige a `gpt-5.6-luna`. El valor por defecto no demuestra el valor de producción ni que cada respuesta haya usado un modelo. Las ejecuciones activas y sus identificadores se documentan en el informe global de evaluación.

`modelConversationPlan` devuelve antes de la llamada en correcciones de apps, privacidad, contexto digital ambiguo y follow-ups reconocidos. Sin API key usa fallback; ante errores ambos planners también usan fallback. Por eso un chat identificado como «BM/Luna» puede haber sido resuelto enteramente por heurísticas. La evidencia diferencial debe guardar `source`, modelo solicitado, modelo devuelto por la API, error, entrada serializada y resultado anterior/posterior a cada capa. Una etiqueta de app o un porcentaje de una suite no demuestra equivalencia con una conversación directa.

### 2. El contexto no era el mismo entre superficies

| Superficie | Entrada y memoria observadas en la base | Transformación de salida / riesgo |
| --- | --- | --- |
| WhatsApp Meta | `whatsapp-agent.js:agentContext`: memoria por identificador de canal, snapshot de app, 8 mensajes de 420 caracteres, TTL 2 horas. Extrae apps y momentos por regex. | `pending_followup_prompt` podía sustituir el input real por una orden de límite diario. `appLink` usaba revisión nativa, pero hacía algunos defaults propios. |
| WhatsApp Twilio / SMS | `sms-agent.js:askBAI`: comparte handler BM y memoria, pero su extractor solo guardaba almuerzo; no hacía la reescritura Meta de límite diario. | `actionDeepLink` usaba rutas antiguas (`start-focus`, `mode`, `apply-plan`, `daily-limit`), añadía 25/30 minutos, omitía días semanales y apps en algunas acciones. La ruta `start-focus` activa directamente en `BlankApp.swift`. |
| Web | Repo separado `blanked-landing/app/chat/conversation.tsx:getBAIReply`: `web_preview`, sin selección ni permisos, memoria inferida de texto + 8 turnos recientes. | `webCapReply` reescribía/añadía texto incluso después del backend. Ante fallo de red usa otro planner regex local. No recibía ni devolvía estado semántico explícito. |
| iOS | `ContentView.swift:AgentContext.serializedPayload`: catálogo de modos, horario, métricas, presencia y memoria larga + 8 mensajes. El input actual también podía estar incluido en el historial. | `RemoteAgentPlan.clean` recortaba a 180 caracteres; los mappers inventaban defaults si faltaban datos. Ante fallo remoto `runPrompt` ofrecía acciones desde `BlankedAgentPlanner`, sin el gate del backend. No guardaba estado semántico. |
| Android | `DigitalWellnessRemoteStore.kt` transporta `bm-loop`; `MainActivity.kt` tiene identidad/handoff. No hay llamada conversacional a `blanked-agent` en `app/src/main`. | No existe evidencia de un chat BM Android equivalente al iOS. Una prueba backend con `channel=android` valida un adaptador contractual, no una interfaz nativa inexistente. |

Los snapshots de app son sincronizados; no son observación en tiempo real del dispositivo. WhatsApp/SMS requieren presencia reciente para enlaces; iOS vuelve a comprobar permisos al ejecutar. La presencia y los permisos cumplen funciones distintas.

### 3. El schema pedía decisiones ejecutables al modelo sin un estado semántico

`blanked-agent.js:agentSchema` exige `interpretation`, `behavior_pattern`, `next_move` y un plan completo con título, CTA, 2–4 bullets y acciones. `actionSchema` requiere nueve campos aunque casi todos sean nulos; fija minutos 5–240. No recoge qué dato se corrigió, procedencia, confianza, slots pendientes, confirmación vinculada a una propuesta o una revisión de estado.

El prompt pide naturalidad, pero simultáneamente pide estructura, marca, explicaciones de producto y posibilidades de ejecución. Incluye el ejemplo `Block Instagram from 10 to 7` interpretado como 22:00–07:00 sin preguntar meridiem/recurrencia. También presenta duraciones recomendadas sin que el usuario las haya elegido. La instrucción de no mencionar «patterns» convive con ejemplos que exigen `Pattern:`. `speech_text` pide una nota de voz aunque el producto haya deshabilitado respuestas de audio. Estos conflictos existen en la entrada; no prueban por sí solos un fallo del modelo.

### 4. Había varias autoridades semánticas consecutivas

Flujo de la base:

```text
input del proveedor
  → extracción de memoria por canal / posible reescritura Meta
  → buildAgentContext y allowlists
  → shouldUseAppLayer / classify
  → fallbackPlan + modelo estructurado, o conversación sin schema
  → resolveBlockingContract (invocado en más de una capa)
  → actionGate (fallbacks y listas de títulos especiales)
  → normalizePlan / conversationalMessage / localizePlan
  → canal: CTA, resumen, enlace, recorte
  → app: decode/map/defaults → confirmación o ruta antigua directa
```

`normalizePlan` conserva la presentación del fallback según listas de títulos; puede descartar una respuesta del modelo semánticamente mejor. `actionGate` reconstruye el contrato desde prompt, contexto y propuesta del modelo, y tiene returns tempranos de fallback. `normalizeActionForPrompt` puede borrar minutos en un follow-up porque solo busca la duración en el input actual. `normalizeAction` convierte valores fuera de rango en otros valores válidos y añade defaults en algunas conversiones. Un parser, un modelo, el gate y el cliente pueden coincidir parcialmente y aun así producir texto y acción incompatibles.

### 5. La persistencia era textual, parcial y sensible al orden

`_assistant_channel.js:recordConversationTurnState` deduce el slot pendiente del texto escrito por BM usando regex para bedtime, comida, trabajo y despertar. Cambiar una formulación rompe ese estado. `pending_blocking` era otro objeto separado, almacenado solo cuando `blocking_user_request=true` y borrado al completar el contrato. Completar los slots no equivale a ejecutar; borrar el estado aquí dificulta confirmar o corregir después.

`getAssistantMemory` recompone los últimos 20 eventos de una tabla compartida con conexión/contexto/procesamiento. No carga el último valor durable de cada tipo; muchos eventos recientes pueden expulsar hechos anteriores. La deduplicación por mensaje evita reintentos idénticos, pero no demuestra orden/serialización entre dos mensajes diferentes enviados simultáneamente. Esta rama añade la migración 015 y un almacén dedicado con compare-and-swap (CAS: solo actualiza si la versión leída sigue vigente). La migración no se ha aplicado al servidor.

## Cambios realizados en esta rama

1. WhatsApp Meta conserva el input original: se elimina `pending_followup_prompt`. WhatsApp y SMS pasan `plan.semantic_state` al registro de conversación. La normalización común conserva el estado; `_bm_semantic_store.js` y la migración 015 proporcionan lectura/escritura con versión independiente y TTL de 2 horas.
2. `_bm_action_link.js` centraliza enlaces `review-action` para Meta/Twilio/SMS. Conserva apps, minutos nulos, medianoche y weekdays; rechaza ventanas incompletas/degeneradas. Un picker sin parámetros sigue siendo setup. SMS deja de fabricar 25/30 minutos en enlace/resumen, usa las apps del contrato corregido y solo permite la plantilla aprobada de revisión.
3. Web devuelve el último `semantic_state` del backend en cada petición y preserva el texto canónico. Cambio de tres líneas funcionales en repo separado, commit `f93e83e` de `codex/bm-semantic-audit`; sin publicación Sites.
4. iOS transporta y persiste el JSON semántico completo con TTL de 2 horas y límite de 64 KiB; no depende de los últimos 8 mensajes. Preserva la respuesta canónica completa. Ante fallo remoto devuelve cero acciones y permite reintentar.
5. `tools/bm_channel_contract_test.js` comprueba equivalencia de los enlaces de Meta/SMS, parámetros exactos, correcciones de apps, medianoche/recurrencia y ausencia de datos inventados en setup. El holdout independiente contiene 12 conversaciones/30 turnos, congeladas antes de su primera ejecución y antes de leer reducer/oracle; su manifiesto guarda SHA-256.

## Persistencia y comandos SMS: resultado final

La migración `015_assistant_semantic_conversations.sql` guarda sesiones por identificador de canal hasheado, limita el JSON a 64 KiB y controla versión y caducidad. Su RPC bloquea la fila y rechaza una versión antigua. Al caducar conserva la versión para que un escritor atrasado no pueda sobrescribir una sesión nueva. El acceso queda limitado a service role. Producción exige este almacén por defecto; `BM_SEMANTIC_PERSISTENCE=legacy` es una excepción diagnóstica explícita, sin garantías de concurrencia.

WhatsApp/SMS confirman la escritura antes de emitir respuestas o enlaces. Los errores de lectura/escritura en modo required se propagan; un conflicto libera la reserva del mensaje entrante para que el proveedor pueda reintentar. La sesión dedicada ausente o caducada no se reconstruye desde eventos viejos. Los logs de auditoría no pueden invalidar una escritura CAS ya confirmada.

El comando SMS `OPEN` solo reutiliza una propuesta si conserva confirmación, fingerprint, estado y presencia recientes. El cache caduca a las 2 horas y el enlace se reconstruye desde el estado canónico para comprobar ruta, apps y parámetros exactos. Toda corrección o cancelación invalida el cache; incluso si falla el borrado del evento, el fingerprint/estado vigente bloquea el enlace viejo. Enlaces antiguos sin TTL/fingerprint, modificados o con rutas de ejecución directa se rechazan.

## Validación local y límites

- Pasan `bm_channel_contract_test`, `bm_semantic_store_test` y `bm_sms_pending_action_test`: paridad de enlaces, parámetros exactos, CAS simulado, caducidad y protección de versión, errores required, liberación para reintentos, corrección/cancelación seguida de OPEN, fallos de borrado y rechazo de enlaces alterados.
- Pasan `whatsapp_agent_smoke_test` y `sms_agent_voice_smoke_test`. Conservan cobertura de audio/transcripción, firma y duplicados. Las propuestas ahora completan recurrencia/horizonte y confirmación antes del enlace; sus mocks respetan el orden descendente de eventos de Supabase.
- Web: `npm run build` pasó con 18 rutas y `npx --no-install oxlint app/chat/conversation.tsx --deny-warnings` pasó. Comandos, códigos de salida, hash y logs de la repetición final están en `tmp/bm-semantic/web-validation.json`. El lint general incluye artefactos generados de `_site-package-stage` y falló fuera del archivo cambiado. El baseline del transporte web se conserva en `tmp/product-harness/web-transport-baseline.json`; no existe harness propio en ese repo.
- La revisión independiente v2 conserva las expectativas originales y documenta tres errores de fixture: dos convenciones de días y la necesidad de selección exacta tras quitar una app. Ocho turnos originales pasan revisión semántica completa. Un derivado expresamente marcado desarrollo, no holdout, pasa 11/11 con revisión de todas las superficies. El nuevo holdout v3, congelado antes de ejecutarlo, detectó dos errores reales en tres turnos: ignorar una corrección de hora final e ignorar una cancelación. Su primera ejecución y las revisiones de nueve respuestas equivalentes y tres no equivalentes permanecen intactas; no constituyen 100% reservado. Los resultados posteriores corresponden al informe global.
- El CAS se verificó con dobles de prueba que simulan la RPC; no se ejecutó la migración ni concurrencia real en Postgres. Docker local no tiene daemon disponible. No hay pruebas físicas con proveedores/dispositivo. El product harness global se ejecuta al integrar los cambios.

No hay compilador Swift en este Windows: los cambios iOS se inspeccionaron estáticamente, sin afirmar compilación, firma, TestFlight o ejecución física. Las rutas antiguas de deep link permanecen por compatibilidad, pero estos canales ya no las generan. El estado de ejecución real sigue perteneciendo al loop y al dispositivo; el estado conversacional autoriza una propuesta para revisión.

No se ha demostrado paridad de UI Android; los casos con ese canal solo prueban el contrato del backend. La revisión de equivalencia textual la realiza un agente independiente, no una persona; está vinculada por hashes a expectativas y superficies completas. Las métricas duras, la naturalidad y la comparación con un modelo directo se informan por separado. Los fallos originales de los holdouts no se eliminan después de usar sus casos para corregir el sistema.

### Cierre de la evaluación reservada

Después del freeze del core de 82 pruebas y del oracle de 42 mutaciones se creó `bm_semantic_heldout_v4.json`: 5 conversaciones nuevas, 11 turnos, expectativas escritas antes de ejecutarlos. Su manifiesto guarda SHA-256 `f4b7500e723b55126b62d8c6b6c6b7c3a85abd547fd594e5fd243b24de2e91b3` con saltos LF. El primer run pasó todas las comprobaciones duras; la revisión independiente posterior de mensaje, respuesta, voz, título y botones aprobó 11/11. Evidencia: `tmp/bm-semantic/heldout-v4-reviewed.json`. Incluye las cinco etiquetas de canal, selección exacta, días ISO frente a nativos, modo estricto inmediato, español y horizonte contestado en otro turno. Es una muestra acotada y usa el backend determinista; no demuestra perfección general ni ejecución física.

El v3 ya consumido pasa ahora 12/12 con revisión independiente de las respuestas corregidas (`tmp/bm-semantic/v3-repaired-reviewed.json`); el informe inicial de tres fallos y sus revisiones negativas permanecen intactos. Los siete turnos de extractos observados también cuentan con revisión semántica independiente en `bm_production_observed_reviews.json`; la procedencia incompleta de los logs impide llamarlos siete conversaciones humanas reales.
