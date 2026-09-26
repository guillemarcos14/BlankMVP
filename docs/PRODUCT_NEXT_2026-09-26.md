# Blank: conversación recuperable y protección fiable

## Qué cambia para la persona

La conversación principal conserva la referencia aprobada: tres puntos, una respuesta legible, una acción concreta cuando existe y un campo compacto con dictado. El menú da acceso directo a distracciones, horarios, progreso y ajustes. El modo oscuro depende de la protección activa. No se inventan datos de uso ni se confunde una orden preparada con una protección aplicada.

Un mensaje pendiente conserva su UUID y texto original en Keychain, separado del siguiente borrador y vinculado a la identidad de la cuenta. Cerrar la app, perder la conexión o renovar la sesión permite recuperar la misma operación. La respuesta no borra lo que se ha escrito después. Los errores indican cómo recuperarse; la paginación y los cambios de cuenta no mezclan conversaciones.

Una respuesta posterior sin acción ya no hace inaccesible una orden pendiente anterior: el historial permite recuperarla mediante su botón de aplicación. Al abrirlo se actualiza el estado autenticado; los datos en caché, una carga fallida o un cambio de cuenta no habilitan acciones. Antes de aplicar se consulta de nuevo el turno y se exige que conserve el mismo ID de acción y un estado aplicable. La ejecución continúa por la bandeja y el acuse nativos existentes.

## Auditoría y prioridades

| Recorrido | Problema comprobado | Resolución / evidencia requerida |
| --- | --- | --- |
| Identidad y onboarding | Tres pantallas candidatas todavía no distribuidas; sesión concurrente podía competir al renovar tokens | Se conserva OTP/consentimiento, preparación nativa y WhatsApp verificado; renovación única y cambio de cuenta protegido. Falta alta física en build firmada. |
| Conversación y memoria | Failed quedaba sin recuperación, reintento podía cambiar texto/UUID y una respuesta antigua sobrescribir otra nueva | Turno durable, lease por usuario, checkpoint transaccional con memoria compartida BM Final, reintento del mismo payload y control de revisiones en iOS. |
| Historial | Empates de fecha podían omitir turnos; error al cargar se ocultaba; acuse podía perderse al cambiar de acción; una respuesta posterior ocultaba el CTA pendiente anterior | Cursor compuesto, errores visibles, recibos terminales durables y CTA recuperable en su turno anterior. Snapshot actualizado al abrir y consulta de estado con ID exacto antes de aplicar; JWT, instalación y dueño verificados en cada lectura. |
| Voz | Tap de audio huérfano y permisos/callbacks tardíos podían reiniciar o detener otra grabación | Inicio/cancelación por generación, limpieza del tap independiente del motor y revisión antes de enviar. Micrófono real pendiente. |
| Bloqueo y selección | Selector abierto podía cambiar distracciones durante protección; flags locales podían anunciar éxito aunque fallase DeviceActivity | Autoridad en SessionStore, selección fija mientras cualquier protección está activa y acuses condicionados al registro nativo. El simulador no prueba bloqueo físico. |
| Horarios y notificaciones | Faltaban en la rama los fixes `33ce6fe` y `256c376`: días no diarios, caducidad por ventana, shields independientes, recibos obsoletos y taps perdidos | Recuperación selectiva, compatibilidad de ventanas antiguas y pruebas ejecutables del modelo app/extensión. |
| Progreso y ajustes | Acceso indirecto desde conversación y texto de navegación con contraste insuficiente | Acceso directo desde el menú y contraste reforzado; métricas siguen usando los datos existentes. |
| Backend Cloud | Producción carece de `assistant-app`; validación local permitía llamar al deploy sin evidencia de release | Integración separada, migraciones aditivas y preflight obligatorio de evidencia exacta antes de cualquier mutación remota. |

Prioridad aplicada: pérdida de mensajes/estado y ejecución falsa (alta frecuencia e impacto), regresiones de horarios/recibos (riesgo funcional), acceso/legibilidad, y eliminación demostrada de residuos. La comprobación del runtime y del estado instalado precede a retirar compatibilidad.

## Limpieza comprobada

Se retiran únicamente las dos copias MP4 del bundle iOS, el imageset iOS `blank_logo_white` y la vista privada `ReportLiquidBackground`, sin consumidores tras buscar referencias de Swift, Xcode y extensiones. Los archivos retirados suman 2.585.250 bytes, sin atribuir esa cifra al tamaño comprimido de descarga. Se conservan los vídeos usados por la preview web y el logo Android, así como NFC, CONNECT y adaptadores legacy que siguen teniendo consumidores o instalaciones compatibles. Las migraciones históricas permanecen intactas.

## Evidencia y límites

La auditoría añadió dos controles de aislamiento: el teléfono por sí solo ya no permite consultar la bandeja, y todas las escrituras de acciones pendientes de app, WhatsApp, SMS, onboarding, polling y acuses pasan por versión semántica o comparación de acción/estado bajo el mismo lock. STOP y cambio de conexión invalidan además la generación, incluyendo trabajos preparados que aún no se habían encolado. Una caducidad inferida no sustituye al acuse del iPhone: un recibo tardío debe validarse contra su envelope original y no modificar una acción posterior.

La batería antigua de 48 turnos tenía dos trayectorias realmente distintas. El nuevo corpus de desarrollo contiene 40 casos base y cinco continuaciones por caso: 200 trayectorias de entrada/contexto/expectativa, 160 secuencias textuales y 925 turnos; no son 200 problemas independientes ni un holdout. Permitió corregir la pérdida de horarios al elegir bloqueo normal, la pérdida de inicio al rechazar una duración y la eliminación silenciosa de una expiración solicitada que el límite diario nativo no soporta.

La primera ejecución real completa se conserva en `tmp/bm-semantic/product-next-live-first.json`: intención, transiciones y acciones coinciden en 925/925; diez errores de slots pertenecen a duración histórica contaminando una petición nueva, y tres fallos de extracción usaron fallback. El juez original aprobó 88,43 %, con 107 respuestas pobres y 67 contradicciones/claims duros, mezclando defectos reales con errores del evaluador. No cumple release. Veinte rechazos léxicos fueron revisados como referencias/negaciones/rangos y pasaron a **unverified**, no aprobados. El juez recibió después el contrato nativo para evitar confundir días ISO con Calendar o inventar capacidades de límites diarios; no se cambian los umbrales.

El segundo intento de evaluación devuelve `429 insufficient_quota` por créditos agotados. Las correcciones posteriores se validan localmente; no se atribuye a su código la evaluación live anterior ni se declara resuelta su calidad generativa. También faltan build firmada y evidencia física de iPhone. La API de staging y sus fixtures son independientes de producción y nunca constituyen prueba de Screen Time.

La base es PR #5 (`58cdc55`); baseline anterior a las ediciones en `tmp/product-harness/baseline.json`. El cierre exige harness con `--enforce-scope`, pruebas de transporte y autenticación, SQL ejecutado en PostgreSQL aislado, regresiones nativas Swift, compilación iOS/Android y capturas del propio SwiftUI en simulador.

Los fixtures visuales solo existen en Debug bajo `BLANK_UI_SCENARIO`, no usan cuentas ni llaman al backend y no acreditan ejecución de Screen Time. El runner prepara siete capturas: claro con acción (`phone-action.png`), protección activa (`phone-active.png`), error con borrador (`phone-error.png`), vacío (`phone-empty.png`), sesión (`phone-signin.png`), accesibilidad tipográfica (`phone-dynamic-type.png`) e historial (`phone-history.png`). Esta última usa el componente real con una acción pendiente y un turno posterior sin acción; el botón aparece habilitado, pero el fixture no ejecuta callbacks nativos. La revisión visual debe atribuirse al commit que generó el artefacto CI, sin trasladar capturas anteriores al candidato actual. Las pruebas de modelo deben distinguir respuestas reales de fallbacks, repeticiones y corpus únicos. Ningún contador automatizado equivale a una mejora «10x» demostrada: esa hipótesis necesita datos de uso posteriores.

Producción observada al iniciar: Netlify `6ab506f5f541c324210b075f`, asociado en Brain a `9b2e56c`, sin `commit_ref` remoto; función `assistant-app` ausente y su URL devuelve HTML por fallback. Supabase conserva versiones 001–021 y carece de la tabla 022. No confundir HTTP 200 con endpoint operativo.

## Integración y recuperación

La rama de release se prepara desde `0164fdc` y el candidato completo, evitando el `main` divergente. Aplicar 022, 023 y 024 en ese orden únicamente tras los gates. La 024 restaura de forma aditiva el esquema legacy que otra rama publicó con número 020; no se repara ni reescribe historial remoto.

Antes de desplegar se exige `backend_release.js --mode deploy --confirm --release-evidence <ruta>`, con candidato exacto, evidencia de modelo/juez, build firmada y casos físicos exigidos por el gate. Preservar el deploy anterior para rollback; las tablas nuevas son aditivas y permanecen para conservar datos. Después del deploy contrastar artefactos/digests y exigir 401 JSON sin JWT, aislamiento de cuentas, recuperación durable, APNs y acuse nativo. Una build de simulador, un push aceptado o una fila guardada no prueba bloqueo real.
