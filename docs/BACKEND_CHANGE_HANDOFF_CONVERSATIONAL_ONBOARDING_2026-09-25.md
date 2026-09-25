# Entrega a integración Backend Cloud — onboarding conversacional

Objetivo: Sustituir la encuesta iOS por activación nativa y conversación posterior en BM Final, conservando perfil personal explícito y verificación real de dispositivo.

Rama: `codex/production-app-onboarding-2026-09-24`

Commits: `6c102c3`, `93e3cf5`, `b3318ad` (más este handoff).

Archivos/superficies modificadas:
- `ios/Blank/Blank/SetupView.swift`: ocho pasos activos; encuesta y estimaciones no verificadas fuera del recorrido; conexión WhatsApp con verificación de canal y APNs; SMS tras flag de build.
- `ios/Blank/Blank/HomeView.swift` y `ReportView.swift`: títulos interiores alineados con la tipografía Inter semibold del onboarding; consentimiento telefónico sin imponer un canal en el texto.
- `netlify/functions/sms-agent.js`: hechos explícitos de nombre, edad y objetivo extraídos en BM Final y guardados en la memoria de canal y el contexto compartido.
- `netlify/functions/assistant-channel.js`: la sincronización de app conserva nombre, edad y perfil; `complete_onboarding` usa el canal vinculado sin relajar identidad, lista nativa, permisos o APNs.
- `netlify/functions/bm-onboarding.js` y `bm-personal-context-view.js`: el chat no declara listo el iPhone antes del acuse; la edad explícita puede usarse en el contexto personal.

Migraciones Supabase: ninguna.

Variables de entorno: ninguna nueva. `BM_FINAL_APP_LINKED_ROUTING_ENABLED` sigue siendo la barrera de activación pública. La clave de Info.plist `BlankFinalSMSOnboardingEnabled` permanece ausente/falsa: no habilitar SMS en la app antes de probar su enrutamiento BM Final, incluido el worker asíncrono de waitlist.

Validaciones ejecutadas:
- `node tools/product_harness.js --contract tools/product_harness_contract.json --baseline tmp/product-harness/baseline.json --enforce-scope`: 50/50.
- `node tools/bm_global_context_test.js`, `node tools/sms_agent_voice_smoke_test.js`, `node tools/whatsapp_agent_smoke_test.js`: correctos.
- iOS Debug simulador en GitHub Actions `36129968556`: correcto. Una compilación posterior para `b3318ad` está pendiente al escribir este handoff.
- `git diff --check`: correcto.

Pruebas pendientes:
- Integración protegida de Backend Cloud y comprobación de digests exactos antes de cualquier deploy.
- Build firmada, revisión visual en dispositivo, alta nueva y WhatsApp → notificación → bloqueo con acuse `verified`.
- SMS BM Final: ruta de Twilio/worker, vínculo, respuesta y acuse físico antes de activar `BlankFinalSMSOnboardingEnabled`.

Riesgos o conflictos conocidos: el tráfico público actual de SMS aún entra en Early Access. La UI del nuevo onboarding lo mantiene desactivado hasta cerrar esa ruta; los smokes locales no acreditan el transporte SMS productivo.
