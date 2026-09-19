# Entrega a integración Backend Cloud

Objetivo: activar una capa temporal de Early Access conversacional para todas las altas, aislada del Blankmind agéntico.

Rama: `codex/waitlist-early-access-2026-09-19`

Commit: HEAD de esta rama (`git rev-parse --short HEAD`).

Archivos/superficies modificadas:

- Functions `waitlist-start`, `waitlist-agent`, `waitlist-data` y módulos `_waitlist_*`.
- Landing `/early-access`, redirects, CTA y privacidad.
- Contrato del product harness y pruebas específicas de waitlist.
- Documentación y ejemplo de variables de entorno.

Migraciones Supabase:

- Aplicar `supabase/migrations/019_waitlist_early_access.sql` después de `018`.

Variables de entorno:

- `WAITLIST_EXTRACTION_MODEL=gpt-5.6-luna`, `WAITLIST_CONVERSATION_MODEL=gpt-5.6-sol` y `WAITLIST_CONVERSATION_POLISH=true` para priorizar naturalidad.
- `WAITLIST_WHATSAPP_PROVIDER`.
- Twilio: `WAITLIST_WHATSAPP_OPENING_CONTENT_SID_1`, `WAITLIST_WHATSAPP_OPENING_CONTENT_SID_2`, `WAITLIST_TWILIO_WEBHOOK_URL`.
- Meta: `WAITLIST_WHATSAPP_OPENING_TEMPLATE_1`, `WAITLIST_WHATSAPP_OPENING_TEMPLATE_2`, `WAITLIST_WHATSAPP_TEMPLATE_LANGUAGE`.
- `WAITLIST_PUBLIC_URL`.
- Mantener `WAITLIST_ALLOW_FREEFORM_OPENING=false` en producción.

Validaciones ejecutadas:

- `node tools/waitlist_early_access_test.js`: verde.
- `node tools/waitlist_conversation_eval.js`: `9/10` con juez independiente; el único rechazo fue una fórmula de coaching que después quedó bloqueada por el validador final.
- `node tools/product_harness.js --contract tools/product_harness_contract.json --baseline tmp/product-harness/baseline.json --mode validate --enforce-scope`: `44/44`, cero reparaciones.
- `node tools/waitlist_early_access_test.js`: verde tras el cierre.
- `git diff --check`: verde; solo avisos de conversión LF/CRLF.

Pruebas pendientes:

- Aplicar SQL en Supabase real.
- Aprobar/configurar las dos plantillas exactas.
- Smoke interno real de alta, texto, audio, duplicado, `STOP`, exportación y borrado.

Riesgos o conflictos conocidos:

- No desplegar directamente desde esta rama de implementación.
- Cambiar el webhook deja dormido el endpoint final, pero no modifica su código ni sus datos.
- Sin plantillas aprobadas, WhatsApp rechazará los dos mensajes iniciados por Blankmind.
