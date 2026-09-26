# Conversación in-app de BM Final

## Contrato

- `assistant-app` exige un JWT vigente de Supabase y un `app_install_id` que coincida con la identidad autenticada. El cliente iOS guarda access/refresh tokens en Keychain tras OTP y renueva la sesión mediante `app-auth`.
- `history` pagina los turnos propios de 60 en 60. `send` usa `turn_id` UUID idempotente y guarda la entrada y la salida en `assistant_app_turns`. La pantalla principal muestra solo la última salida; el menú permite recuperar el historial completo, incluidas las entradas del usuario.
- El turno llama a `callBlankedAgent` de BM Final con la misma memoria semántica, perfil canónico y selección de distracciones que WhatsApp. No crea un agente ni un prompt alternativo. La app no envía una copia del turno por WhatsApp.
- Una acción válida se encola en la misma bandeja nativa con ID `app_...`; `Apply now` usa el polling y el acuse existentes del iPhone. La interfaz solo muestra `verified` tras el recibo físico. Los avisos de reintento y resultado de esta acción se consultan en la app, sin mensaje saliente de WhatsApp.

## Release protegido

1. Integrar el commit de esta rama desde `docs/BACKEND_INTEGRATION_WORKFLOW.md` en `codex/backend-release-*`, con baseline del product harness.
2. Comprobar esquema e historial de Supabase. Aplicar `022_assistant_app_turns.sql` antes de exponer `assistant-app`; no reparar historial remoto automáticamente.
3. Validar `node tools/assistant_app_test.js`, smokes BM Final y product harness `--enforce-scope`. Publicar Netlify y Supabase solo desde la conversación de integración con `backend_release.js --confirm`.
4. Compilar y distribuir la app iOS firmada. Probar en iPhone OTP, sesión renovada, continuidad WhatsApp/app, voz, historial, propuesta, `Apply now`, selección canónica, APNs y acuse `verified`/`failed`.

La build de simulador comprueba compilación, no firma ni ejecución de Screen Time en iPhone. Un acuse APNs aceptado tampoco demuestra bloqueo aplicado.
