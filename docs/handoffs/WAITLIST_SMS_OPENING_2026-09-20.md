# Entrega de cambio a integración Backend Cloud

Objetivo:
Corregir la apertura Early Access para que los dos mensajes deterministas se entreguen por el canal elegido en la landing, incluido SMS.

Rama:
`codex/waitlist-early-access-2026-09-19`

Commits:
- `a7b530d Merge SMS waitlist channel parity into release`
- Incluye `7aa9a80`, `ee7b5c1`, `7bc4d11` y `b3bff28`.

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

Despliegue completado:
- Supabase confirmó la base al día y publicó `digital-wellness-features`.
- Netlify `getblank` publicó `6aaf177f922598756a350efb`.
- Falta únicamente la prueba física: seleccionar Message con un teléfono de Estados Unidos o Canadá, confirmar los dos SID SMS en Twilio y responder al primero para verificar `waitlist-agent`.

Riesgos o conflictos conocidos:
- Los cambios de producción deben seguir saliendo desde la rama de integración.
