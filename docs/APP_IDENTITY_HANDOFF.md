# Blankmind Web/App Identity Handoff

## Flujo principal

1. El usuario verifica su teléfono en la web con Supabase OTP.
2. `account-data` crea una identidad única por teléfono y un `assistant_connect_code` interno.
3. Al abrir un conector nativo, el workspace crea un handoff aleatorio con una hora de vida.
4. `blankmind.ai/open?action=handoff&token=...` abre la app por Universal Link/App Link.
5. La app consume el token una sola vez y guarda el código interno; no reutiliza el OTP web.
6. El siguiente mensaje desde ese mismo teléfono en WhatsApp/SMS se asocia automáticamente a la identidad.

## Entrada directa desde App Store

La app mantiene un fallback explícito `Sign in with your phone`. Pide un OTP nuevo, verifica contra Supabase y llama a `app-handoff?action=claim_identity` para enlazar el `app_install_id`.

El código `CONNECT` antiguo sigue operativo para instalaciones y usuarios que aún no han migrado.

## Operación

- Aplicar `supabase/migrations/013_identity_handoffs.sql` antes de desplegar las funciones.
- Configurar `SUPABASE_ANON_KEY` o `SUPABASE_PUBLISHABLE_KEY` en Netlify para el OTP directo desde app.
- Publicar el AASA y `assetlinks.json` en `blankmind.ai/.well-known/`.
- Validar con una cuenta real: web OTP → Open in app → mensaje WhatsApp → reinstalación/entrada directa.
