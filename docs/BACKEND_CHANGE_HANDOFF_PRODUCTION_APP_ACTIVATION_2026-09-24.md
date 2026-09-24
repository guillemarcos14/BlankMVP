# Entrega a integración Backend Cloud: activación desde la app

Objetivo: enrutar a BM Final únicamente a usuarios con app vinculada y WhatsApp conectado desde el teléfono verificado. Anunciar y permitir bloqueos solo tras comprobar permisos, distracciones y APNs. Mantener Early Access para el resto.

Rama: `codex/production-app-onboarding-2026-09-24`

Commit: `6a1d71b`

Archivos/superficies modificadas:
- iOS: `BlankApp.swift`, `ContentView.swift`, `HomeView.swift`, `SetupView.swift`.
- Backend: `app-auth.js`, `assistant-channel.js`, `_identity.js`, `_assistant_channel.js`, `bm-context.js`, `whatsapp-agent.js`, rutas de `waitlist-agent` y dispatcher Twilio. El endpoint existente `app-handoff.js` se reutiliza para `claim_identity`.
- Contrato y documentación: `tools/production_app_activation_test.js`, `tools/product_harness_contract.json`, `docs/PRODUCTION_APP_ACTIVATION.md`.

Migraciones Supabase: ninguna nueva. Requiere que `blankmind_identity_links` de la migración de identidad ya exista en el proyecto de producción.

Variables de entorno: `BM_FINAL_APP_LINKED_ROUTING_ENABLED` queda ausente o distinto de `true` durante integración y QA. Activarla solo después de build firmada, instalación y prueba física completa. `BM_FINAL_QA_WHATSAPP_PHONE` conserva la excepción privada.

Validaciones ejecutadas:
- `node tools/product_harness.js --contract tools/product_harness_contract.json --mode validate --baseline tmp/product-harness/baseline.json --enforce-scope`: 50/50.
- GitHub Actions `iOS Build` run `36021559674`: compilación de simulador correcta.

Pruebas pendientes: build firmada/TestFlight, OTP SMS nuevo, selección en FamilyActivityPicker, permiso de Tiempo de uso, CONNECT desde el mismo número, registro APNs, recepción de ambos mensajes de estado y bloqueo con acuse nativo `verified`. Comprobar otro WhatsApp y SMS para confirmar que siguen en Early Access mientras la variable está desactivada.

Riesgos o conflictos conocidos: la compilación de simulador no verifica firma, APNs ni permisos reales del iPhone. La ruta pública continúa desactivada. El cambio de número de una instalación ya vinculada requiere un flujo de recuperación de identidad antes de ofrecerlo en la interfaz.
