# Entrega de cambio a integración Backend Cloud

Objetivo:
Corregir la apertura Early Access para que los dos mensajes deterministas se entreguen por el canal elegido en la landing, incluido SMS.

Rama:
`codex/waitlist-early-access-2026-09-19`

Commits:
- `7aa9a80 Fix waitlist opening delivery for SMS`
- `ee7b5c1 Keep waitlist openings idempotent per channel`

Archivos/superficies modificadas:
- `netlify/functions/waitlist-start.js`: valida y propaga `channel`.
- `netlify/functions/_waitlist_whatsapp.js`: añade envío SMS Twilio y conserva WhatsApp.
- `web/landing/early-access.html` y `web/landing/early-access.js`: selector y propagación de canal.
- `tools/waitlist_early_access_test.js`: regresión de alta SMS y sender.

Migraciones Supabase:
- `019_waitlist_early_access.sql` y `020_waitlist_channel_openings.sql`, en ese orden.

Variables de entorno:
- SMS usa las existentes `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` y `TWILIO_MESSAGING_SERVICE_SID` o `TWILIO_FROM_NUMBER`.
- WhatsApp mantiene `WAITLIST_WHATSAPP_*` sin cambios.

Validaciones ejecutadas:
- `node tools/waitlist_early_access_test.js`: verde.
- La misma regresión ejecuta un turno completo por WhatsApp y otro por SMS: ambos pasan por `waitlist-agent`, extraen los mismos tres hechos, persisten evidencia y devuelven respuesta TwiML.
- `node tools/product_harness.js --contract tools/product_harness_contract.json --baseline tmp/product-harness/baseline.json --mode validate --enforce-scope`: `44/44`.
- `node --check` de las tres Functions/scripts modificadas: verde.
- `git diff --check`: verde.

Pruebas pendientes:
- Integrar desde la conversación Backend Cloud, desplegar Netlify y probar alta real seleccionando Message con un teléfono de Estados Unidos o Canadá.
- Confirmar en Twilio el SID de los dos SMS y responder al primero para verificar `waitlist-agent`.
- Si ya existe un usuario que recibió WhatsApp, aplicar `020` antes de probar SMS: sus aperturas SMS tienen flags independientes e idempotentes.

Riesgos o conflictos conocidos:
- Los cambios de producción deben salir desde la rama de integración; esta rama no despliega.
