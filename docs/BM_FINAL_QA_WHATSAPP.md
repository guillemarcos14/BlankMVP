# Acceso privado de Guillem a BM Final por WhatsApp

## Contrato

- La variable de Netlify `BM_FINAL_QA_WHATSAPP_PHONE` contiene **un solo** número E.164 exacto (`+` y entre 8 y 15 dígitos). Sin variable o con un valor inválido, nadie entra en BM Final desde el webhook de WhatsApp.
- El remitente se compara tras validar la firma de Twilio o Meta. Solo WhatsApp del número configurado llega a BM Final. SMS de ese mismo número y mensajes de cualquier otro número siguen en Early Access.
- `waitlist-agent`, `waitlist-agent-background`, `sms-agent` heredado y `whatsapp-agent` heredado aplican la misma ruta de producción. BM Final conserva su memoria y sus acciones separadas de las tablas `waitlist_*`.
- El webhook de Twilio mantiene la cola asíncrona. La tarea de background vuelve a comprobar el número antes de ejecutar BM Final. Audio de Twilio se transcribe antes de entregarlo al agente final.
- En producción se exige la firma del proveedor incluso si `TWILIO_VALIDATE_WEBHOOK_SIGNATURE=false`.

## Publicación desde Integración y deploy Backend Cloud

1. Integrar la rama `codex/bm-final-private-whatsapp-2026-09-24` y ejecutar baseline, harness con `--enforce-scope` y release gate.
2. Configurar `BM_FINAL_QA_WHATSAPP_PHONE` en Netlify producción con el número verificado de Guillem en E.164. No guardar el valor en Git.
3. Confirmar que `WAITLIST_WHATSAPP_PROVIDER`, la URL del webhook Twilio/Meta, el remitente de WhatsApp y las credenciales de BM Final corresponden al mismo canal. Publicar Netlify con `node tools/backend_release.js --mode deploy --confirm --netlify` desde esa conversación.
4. Enviar un WhatsApp desde el número autorizado y verificar respuesta de BM Final, memoria y, con la app conectada, un bloqueo con acuse nativo `verified`. Enviar otro desde un número distinto y confirmar que responde Early Access. Enviar SMS desde el número autorizado y confirmar Early Access.

Hasta completar el paso 4, el acceso privado está validado en código, pero no demostrado en el canal físico de producción. Para cerrarlo de inmediato, vaciar la variable y volver a publicar: todas las entradas de WhatsApp pasan a Early Access.
