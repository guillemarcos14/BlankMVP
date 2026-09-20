# Blankmind Early Access temporal

## Alcance

Esta capa sustituye temporalmente la entrada conversacional de Blankmind para todas las altas. No enruta cohortes y no importa ni ejecuta ninguna capacidad del producto final. Su único objetivo es conocer a la persona de forma natural antes de darle acceso.

La web, Supabase, Netlify y los senders existentes de WhatsApp/Twilio siguen siendo los mismos. El producto agéntico queda intacto y dormido mientras el webhook apunte a `waitlist-agent`.

## Flujo

1. La persona abre `/early-access`, elige WhatsApp o Message, verifica su teléfono con el `app-auth` existente y acepta explícitamente guardar la conversación y recibir mensajes en el canal elegido.
2. `waitlist-start` verifica el JWT y que el teléfono pertenece a ese usuario.
3. Se envían exactamente dos mensajes deterministas, una vez cada uno. En WhatsApp son plantillas aprobadas; en SMS se envían como mensajes Twilio normales:

   - `Hi, welcome to Blankmind Early Access. I’m really glad you’re here. Before I invite you in, I’d love to understand how your phone fits into your life.`
   - `What usually happens when you start scrolling? When does it feel hardest to stop? Tell me your story in your own words. You can write to me or send me a voice note, whatever feels easier.`

4. Desde la primera respuesta, `waitlist-agent` conversa sin guion ni orden fijo. Puede conocer trabajo, estudios, rutinas, entorno, intereses, uso del móvil, apps, momentos de scroll, impacto y cambio deseado.
5. Si llega un audio, se descarga y transcribe en memoria. No se conserva el archivo; solo el texto transcrito.
6. Cada turno extrae únicamente hechos explícitos y guarda evidencia, confianza, estado y correcciones. La conversación usa el perfil actual, pero nunca expone que existe un checklist.

## Límites conversacionales

- Habla en primera persona y en inglés, con tono cercano de asistente personal.
- No da consejos, planes, diagnósticos, promesas ni ejecuta acciones del producto final.
- No solicita contraseñas, direcciones, datos financieros, diagnósticos médicos ni atributos sensibles.
- No toma posición ni invita a debatir guerras, aborto, elecciones, partidos o religión polarizante. Marca un límite breve y vuelve a la experiencia cotidiana de la persona.
- `STOP` retira el consentimiento y detiene toda nueva persistencia.
- Una petición de borrado requiere confirmar con `DELETE` dentro de 24 horas y elimina perfil, mensajes, hechos y eventos asociados.

## Datos

Las migraciones `019_waitlist_early_access.sql` y `020_waitlist_channel_openings.sql` crean tablas y flags de entrega separados del producto final:

- `waitlist_users`: identidad verificada, consentimientos y estado del recorrido.
- `waitlist_messages`: texto entrante, transcripciones y respuestas.
- `waitlist_facts`: hechos explícitos versionados con evidencia y correcciones.
- `waitlist_events`: métricas operativas sin lógica de producto final.
- `waitlist_inbound_claims`: idempotencia y recuperación de webhooks.

Todas tienen RLS y solo son accesibles desde el backend con service role. La vista `waitlist_current_profile` expone el perfil vigente para análisis interno.

En cada turno se conserva el mensaje entrante completo y, en paralelo, se extraen todos los hechos explícitos que contenga, no solo el dato utilizado para la respuesta. El perfil contempla identidad primaria (`preferred_name`, `age`, `age_band`, `email`), trabajo/estudios/rutina, entorno, intereses, responsabilidades, relaciones, energía, relación con el teléfono, aplicaciones, contenido, momentos, disparadores, frecuencia, impacto, sentimientos, intentos previos, objetivos y cambio deseado. Cada hecho conserva evidencia, mensaje de origen, confianza, fecha y versión anterior cuando se corrige. Las listas se acumulan sin perder valores previos salvo que el usuario las corrija o retire explícitamente.

La memoria de temas preguntados y la prevención de preguntas repetidas se aplican solo internamente. No se muestran resúmenes, checklists, menús ni frases de redirección meta; cualquier cambio de foco debe surgir de forma natural de la respuesta anterior.

## Activación

1. Integrar esta rama mediante el flujo de Backend Cloud y aplicar las migraciones `019` y `020`.
2. Crear y conseguir aprobación de las dos plantillas con el texto exacto anterior.
3. Configurar las variables `WAITLIST_*` documentadas en `.env.membership.example`, además de las credenciales existentes de Supabase, OpenAI y Twilio. SMS usa `TWILIO_MESSAGING_SERVICE_SID` o `TWILIO_FROM_NUMBER`; WhatsApp conserva sus plantillas aprobadas.
4. Desplegar Netlify y apuntar temporalmente el webhook entrante del número existente a `/.netlify/functions/waitlist-agent`.
5. Verificar alta, dos mensajes iniciales, texto, audio, duplicados, `STOP`, exportación y borrado con un teléfono interno.

No se debe activar `WAITLIST_ALLOW_FREEFORM_OPENING` en producción. Las conversaciones iniciadas por la empresa requieren plantillas aprobadas.

## Rollback

Volver el webhook a su endpoint anterior y restaurar el deploy previo de Netlify. Las tablas `waitlist_*` pueden mantenerse para conservar los consentimientos y datos ya captados; no es necesario borrarlas ni tocar las tablas del producto final.
