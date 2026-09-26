# Verificación privada de Backend Cloud

La autorización explícita de Guillem del 26/09/2026 permite a esta tarea asumir integración y despliegue. La exposición de una release a usuarios sigue dependiendo de sus gates. La verificación previa se hace en infraestructura separada, sin copiar datos de producción.

## Entorno reservado

- Supabase: `blank-product-staging`, referencia `njqbovsmoowkhhsqmitn`, misma organización y plan Free, región `eu-west-3`.
- Netlify: `blank-product-staging-20260926`, site `2ef5a74e-af70-4893-a5f6-63fb2537720d`, [sitio privado](https://blank-product-staging-20260926.netlify.app).
- Producción permanece en Supabase `vhiikgyyfisejjwqtxfc` y Netlify `59955668-9a9b-4979-a283-63fbf3115fe5`. Ningún comando de staging puede usar esos IDs como destino.

La API de branches respondió `402 entitlement_required`: exige Pro. Se creó un segundo proyecto independiente dentro de la cuota Free, sin cambiar la suscripción. [Límites del plan](https://supabase.com/docs/guides/platform/billing-faq). El proyecto nuevo solo contiene fixtures sintéticos cuando se ejecutan los smokes.

El sitio exige contraseña: comprobación HTTP anónima `401`; sesión autorizada `200`. Netlify utiliza un formulario de contraseña que entrega una cookie; Basic Auth no autentica esta protección. La cookie va en un encabezado independiente y permite conservar el JWT de Supabase en `Authorization`.

Credenciales y cookie se guardan cifradas con DPAPI en `tmp/cloud-stage/*.dpapi` del worktree de implementación. No imprimirlas, incluirlas en informes ni añadirlas a Git. Las variables Netlify pertenecen únicamente al sitio de staging: URL y claves de su propia base, OpenAI y routing público desactivado. No se copian Twilio, Meta ni APNs. No se despliegan cron ni transportes de mensajería en esta verificación.

## Secuencia

1. Congelar, integrar y validar el candidato en `codex/backend-release-*`; mantener su baseline y ejecutar `--enforce-scope`.
2. Ejecutar `supabase db push --project-ref njqbovsmoowkhhsqmitn --dry-run` con la contraseña privada. Revisar las migraciones y aplicarlas exclusivamente al proyecto de staging. No usar el setup SQL de pruebas sobre una base de Supabase.
3. Publicar en el sitio de staging solo las entradas de app/autenticación/planner necesarias, empaquetadas desde el candidato validado. Comprobar protección anónima, JWT, aislamiento entre dos cuentas y recuperación real contra PostgreSQL.
4. Registrar commit, deploy, funciones/digests, versiones SQL y resultado de los smokes. Un acuse enviado por una prueba de API se etiqueta como simulado y no cuenta como Screen Time físico.
5. Para la prueba en iPhone, compilar una build firmada con `BLANK_MEMBERSHIP_API_BASE_URL` apuntando al entorno de QA y preparar su acceso privado; conservar hash de artifact y trazas. El gate productivo exige su evidencia física y revisión de modelo. Tras publicar en producción se repiten los smokes y se registra el nuevo deploy; no atribuir a ese entorno pruebas realizadas solamente en staging.

La matriz SQL completa en staging comprueba instalaciones nuevas. La auditoría de producción confirmó por REST la existencia de las dos columnas SMS de `020` y de `bm_legacy_context_snapshots`; `assistant_app_turns` sigue ausente. El nombre histórico distinto de `020` no autoriza reescribir su historial. `022`–`024` son aditivas.

## Recuperación

Los fixtures de QA y sus credenciales solo pertenecen al entorno aislado. Para una futura retirada se elimina primero el acceso del sitio y después los recursos sintéticos identificados; no se toca la base productiva. Una release productiva conserva el deploy anterior como rollback y mantiene las tablas aditivas para no perder turnos. Los límites de gasto, retención y plan permanecen sujetos al proveedor; no se configuraron servicios de pago ni mantenimiento artificial para evitar pausas del plan Free.
