# Entrega de cambio a integración Backend Cloud

Objetivo:
Corregir la apertura Early Access para que los dos mensajes deterministas se entreguen por el canal elegido en la landing, incluido SMS.

Rama de integración:
`codex/backend-release-waitlist-message-parity-2026-09-20`

Commits:
- `a7b530d Merge SMS waitlist channel parity into release`
- Incluye `7aa9a80`, `ee7b5c1`, `7bc4d11` y `b3bff28`.
- `85fb69c Fix SMS reply channel parity`
- `5004e41` integración de la corrección de respuestas.

Archivos/superficies modificadas:
- `netlify/functions/waitlist-start.js`: valida y propaga `channel`.
- `netlify/functions/_waitlist_whatsapp.js`: añade envío SMS Twilio y conserva WhatsApp.
- `netlify/functions/waitlist-agent-background.js`: entrega las respuestas asíncronas por el canal de entrada, sin convertir SMS en WhatsApp.
- `web/landing/early-access.html` y `web/landing/early-access.js`: selector y propagación de canal.
- `tools/waitlist_early_access_test.js`: regresión de alta SMS, turno completo y sender de respuestas por ambos canales.

Migraciones Supabase:
- `019_waitlist_early_access.sql` y `020_waitlist_channel_openings.sql`, en ese orden.

Variables de entorno:
- SMS usa las existentes `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` y `TWILIO_MESSAGING_SERVICE_SID` o `TWILIO_FROM_NUMBER`.
- WhatsApp mantiene `WAITLIST_WHATSAPP_*` sin cambios.

Validaciones ejecutadas:
- `node tools/waitlist_early_access_test.js`: verde.
- La misma regresión ejecuta un turno completo por WhatsApp y otro por SMS: ambos pasan por `waitlist-agent`, extraen los mismos tres hechos, persisten evidencia y entregan la respuesta en el canal correcto. También cubre audio en ambos canales.
- `node tools/backend_release.js --mode validate --baseline tmp/product-harness/baseline-message-channel-release.json`: pasado, product harness `44/44`.
- `node --check` de las tres Functions/scripts modificadas: verde.
- `git diff --check`: verde.

Despliegue previo completado:
- La base desplegada previamente ya incluye la migración `020`, `digital-wellness-features` y el flujo de apertura SMS.
- El candidato anterior añadió la corrección de las respuestas posteriores por SMS y quedó publicado en Netlify `6aafa9c6762d7bcc14d714ea` desde la rama de integración.
- Después del deploy queda la prueba física: seleccionar Message con un teléfono de Estados Unidos o Canadá, confirmar los dos SID SMS en Twilio y responder al primero para verificar `waitlist-agent`.

## Incidencia física de SMS y corrección — 2026-09-20

Objetivo:
Corregir la entrega parcial de la apertura SMS y evitar que una respuesta recibida por el webhook legacy pierda el contexto waitlist.

Rama:
`codex/backend-release-waitlist-message-parity-2026-09-20`

Commit:
`bce2fa3 Fix waitlist SMS opening and conversation routing`

Archivos/superficies modificadas:
- `netlify/functions/waitlist-start.js`: intenta enviar los dos mensajes deterministas antes de persistir flags; los fallos de persistencia ya no bloquean el segundo envío y se devuelven como advertencia no bloqueante.
- `netlify/functions/sms-agent.js`: deriva usuarios waitlist activos al mismo procesador con historial, incluso mientras el sender siga apuntando al webhook antiguo.
- `netlify/functions/waitlist-agent.js`: fallback contextual para no responder con la frase genérica de BM Final.
- `tools/waitlist_early_access_test.js`: regresión de persistencia fallida, fallback y ruta legacy.

Migraciones Supabase:
- Ninguna nueva; `020_waitlist_channel_openings.sql` sigue siendo necesaria en producción.

Validaciones ejecutadas:
- `node tools/waitlist_early_access_test.js`: pasado.
- Tests de memoria/canales/SMS pendientes de BM: pasados.
- `node tools/backend_release.js --mode validate --baseline tmp/product-harness/baseline-waitlist-sms-fix.json`: pasado, product harness `44/44`.

Pruebas pendientes:
- Confirmar en Twilio los dos SID SMS y responder al primer mensaje con el teléfono real.

Riesgos o conflictos conocidos:
- Deploy realizado tras petición explícita de Guillem: Netlify `6aafc95347501727fa71d1e7`, URL `https://getblank.netlify.app`, commit `243a45c3e447afb3a8ceb81929a5b8977436af80`.

Riesgos o conflictos conocidos:
- Los cambios de producción deben seguir saliendo desde la rama de integración.
