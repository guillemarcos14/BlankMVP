# Estado del proyecto

Ultima actualizacion: 2026-07-11

## Resumen actual
- BlankMVP es un proyecto para Blank, un bloqueador de apps controlado por NFC.
- El repo contiene app Android (`app/`), MVP iPhone (`ios/Blank/`), documentos de lanzamiento (`docs/`) y landing estatica (`web/landing/`).
- Este archivo es la fuente de verdad operativa para continuidad entre sesiones.

## Hecho hoy
- 2026-07-09: Apple Developer Program confirmado activo con Team ID `GS54UV79RG`.
- 2026-07-09: Creados los App IDs `com.blanknfc.app.ios` y `com.blanknfc.app.ios.deviceactivity` en Apple Developer.
- 2026-07-09: Enviado a Apple el request de `Family Controls (Distribution)`; Apple confirmo recepcion y queda pendiente de revision.
- 2026-07-09: En MacinCloud se abrio `~/BlankMVP/ios/Blank/Blank.xcodeproj` con Xcode 26.5.
- 2026-07-09: Build de simulador sin firma verificado con `BUILD SUCCEEDED`.
- 2026-07-09: Se anadio la cuenta Apple en Xcode y aparece el equipo `GUILLEM ARCOS GONZALEZ`.
- 2026-07-09: Se fijo `DEVELOPMENT_TEAM = GS54UV79RG` para app y extension y se subio a `origin/codex/ios-device-activity-target`.
- 2026-07-09: Se anadio `AGENTS.md` con la regla de gestion de estado del proyecto.
- 2026-07-09: Se creo `ESTADO.md` con estructura inicial para decisiones, descartes, estado y proximos pasos.
- 2026-07-09: Capturas del iPhone confirman Apple Developer Program activo para `GUILLEM ARCOS GONZALEZ`, valido hasta 2027-07-09.
- 2026-07-09: El usuario confirma que ya ha anadido su iPhone fisico a Apple Developer.
- 2026-07-09: Se accedio al portal web de MacinCloud y se localizo el servidor `FF523 - user953323`; el login RDP web fallo con "The logon attempt failed".
- 2026-07-09: Creados dos provisioning profiles de desarrollo en Apple Developer: `Blank iOS Development iPhone Guillem` para `com.blanknfc.app.ios` y `Blank Device Activity Monitor Development iPhone Guillem` para `com.blanknfc.app.ios.deviceactivity`, ambos con certificado de desarrollo de MacinCloud e `iPhone Guillem`.
- 2026-07-09: Xcode ya muestra signing de desarrollo valido para `Blank`; el usuario confirma que `BlankDeviceActivityMonitor` tampoco muestra `Try Again`.
- 2026-07-09: En Xcode se autogenero el scheme `Blank`, se selecciono `Any iOS Device (arm64)` y se lanzo build firmado; fallo con `Build input file cannot be found`.
- 2026-07-09: El error exacto de build firmado apunta a un `.mobileprovision` ausente en `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`, no a fallo Swift.
- 2026-07-09: Se restauro el Team `GUILLEM ARCOS GONZALEZ` en `BlankDeviceActivityMonitor` tras quedar en `None`.
- 2026-07-09: `BlankDeviceActivityMonitor` quedo en signing manual con el provisioning profile `Blank Device Activity Monitor Development iPhone Guillem`, Team `GUILLEM ARCOS GONZALEZ` y certificado `Apple Development`.
- 2026-07-09: Se sustituyeron referencias del nombre anterior por `Blank`, incluyendo rutas iOS, target, scheme esperado, fuentes Swift, entitlements, documentacion y enums Android; la busqueda literal del nombre anterior ya no devuelve coincidencias.
- 2026-07-09: En MacinCloud/Xcode se confirmo visualmente que el proyecto, scheme y targets cargan como `Blank` y `BlankDeviceActivityMonitor`; Xcode mostro el aviso de workspace antiguo desaparecido y se cerro sin re-guardarlo.
- 2026-07-09: Tras refrescar signing/provisioning en Xcode, el usuario confirma `0 errores` en el build iOS de `Blank`.
- 2026-07-09: Se intento `Product > Archive` en MacinCloud Pay-As-You-Go para generar IPA; `Product > Build` pasa, pero `Archive` sigue fallando en `ProcessProductPackaging` de `BlankDeviceActivityMonitor` por un `.mobileprovision` local inexistente aunque `Release` muestra `Automatically manage signing` y `Xcode Managed Profile`.
- 2026-07-10: Apple confirmo por correo que el entitlement `Family Controls (Distribution)` ya ha sido asignado a la cuenta y se puede configurar para apps elegibles.
- 2026-07-10: En MacinCloud/Xcode se creo certificado `Apple Distribution`, se corrigio `HomeView.onChange` para iOS 16, se corrigio la inicializacion de `SessionStore` y `Product > Archive` genero un archive llamado `Blank`.
- 2026-07-10: `Validate App` en Organizer fallo al intentar crear automaticamente el app record; `IDEDistribution.verbose.log` indica `missing(appBundleId: com.blanknfc.app.ios)`, es decir App Store Connect no encuentra/asocia ese Bundle ID para crear la app.
- 2026-07-10: App Store Connect ya muestra la app `Blank NFC`; tras quitar `NDEF` de Core NFC y dejar solo `TAG`, `Validate App` completo correctamente: `Blank 1.0 (1) validated`.
- 2026-07-10: `Distribute App` -> `App Store Connect` -> `Upload` completo correctamente en Xcode: `Blank 1.0 (1) uploaded`.
- 2026-07-10: En App Store Connect/TestFlight se completo la informacion de exportacion/encriptacion y el build `1.0 (1)` queda `Lista para enviar`.
- 2026-07-10: Tras instalar Blank en iPhone, el usuario confirma que la autorizacion de Screen Time no queda aprobada aunque acepte el dialogo; se reviso el flujo local y se anadio refresco/diagnostico del estado real devuelto por iOS (`approved`, `denied`, `notDetermined`).
- 2026-07-10: En Apple Developer se verifico en navegador que `com.blanknfc.app.ios` y `com.blanknfc.app.ios.deviceactivity` tienen marcados `Family Controls (Development)`, `Family Controls (Distribution)` y `Family Controls App and Website Usage`; la app principal tambien tiene `NFC Tag Reading`.
- 2026-07-10: Capturas del iPhone muestran que Blank aparece en `Ajustes > Tiempo de uso` bajo `Apps con acceso a "Tiempo de uso"` con el interruptor activado; iOS parece haber concedido el permiso a nivel de sistema.
- 2026-07-10: El iPhone muestra el mensaje `Screen Time no ha quedado autorizado` sin el sufijo nuevo `Estado iOS: ...`, lo que indica que el build instalado probablemente es anterior al diagnostico local; se endurecio el flujo para esperar hasta 2,5s el refresco de `AuthorizationCenter` y avanzar automaticamente al paso 2 si ya esta `approved`.
- 2026-07-11: Se reviso el problema de Screen Time tras la instalacion en iPhone; el codigo local ya tenia diagnostico de `AuthorizationCenter`, y se anadio refresco al volver la app a `active` para que el onboarding avance si iOS concede el permiso desde el dialogo o desde Ajustes.
- 2026-07-11: Se subio el build iOS local a `1.0 (2)` (`CURRENT_PROJECT_VERSION = 2` y `CFBundleVersion = 2`) para preparar una nueva subida a TestFlight con el arreglo de Screen Time.

## Estado actual
- iOS compila en Xcode 26.5 para simulador sin code signing.
- El build iOS de desarrollo en MacinCloud/Xcode ya no muestra errores tras refrescar provisioning; queda pendiente distinguir si fue build para dispositivo, archive o solo build local de desarrollo.
- Archive iOS ya se genero en Xcode como `Blank`; queda pendiente distribuirlo/subirlo desde Organizer a App Store Connect/TestFlight y resolver cualquier validacion de Apple si aparece.
- El build iOS `Blank 1.0 (1)` ya esta subido y se pudo instalar, pero no debe seguir usandose para diagnosticar Screen Time porque parece anterior al arreglo local.
- El acceso RDP a MacinCloud volvio a pedir login al reabrir la conexion; queda pendiente volver a entrar al servidor `FF523` para refrescar Xcode y probar firma.
- Ya existen provisioning profiles de desarrollo para la app principal y la extension, y Xcode ya no muestra el bloqueo inicial de perfiles.
- `Family Controls (Distribution)` ya esta aprobado/asignado por Apple; Xcode ya pudo generar archive tras crear certificado de distribucion y corregir errores Swift.
- El codigo iOS declara Family Controls en los entitlements de la app y de la extension, la llamada usa `AuthorizationCenter.shared.requestAuthorization(for: .individual)`, los App IDs del portal ya tienen Family Controls activado y el iPhone muestra Blank con acceso a Tiempo de uso; el build local ahora espera el refresco de `AuthorizationCenter`, refresca al volver a primer plano y autoavanza el onboarding si el permiso ya esta aprobado.
- La copia de MacinCloud esta en `~/BlankMVP`, rama `codex/ios-device-activity-target`.
- En Windows y MacinCloud la ruta iOS ahora es `ios/Blank/Blank.xcodeproj`; Xcode carga el proyecto renombrado, pero falta validar con build iOS real tras resolver signing/provisioning.
- Existe una convencion de repo para leer y actualizar `ESTADO.md` al inicio, durante y al final de cada bloque de trabajo.
- Hay cambios no relacionados ya presentes en el arbol de trabajo; algunos ficheros que ya estaban modificados tambien recibieron reemplazos de texto del nombre anterior a `Blank`.

## Proximos pasos concretos
- Confirmar si el build con `0 errores` fue `Product > Build` para `Any iOS Device (arm64)` y guardar captura/nota del resultado.
- Si se quiere instalar en iPhone fisico, seleccionar el dispositivo registrado y ejecutar build/run de desarrollo.
- No repetir solo el toggle de `Automatically manage signing`; ya se probo en `Release` con `Clean Build Folder` y el error persistio.
- Resolver el archivo de provisioning de archive para `com.blanknfc.app.ios.deviceactivity` o esperar aprobacion de `Family Controls (Distribution)` antes de insistir con TestFlight/App Store.
- En MacinCloud, actualizar `~/BlankMVP` con estos cambios y generar/subir un nuevo archive `Blank 1.0 (2)` a TestFlight.
- En el iPhone, instalar `Blank 1.0 (2)` desde TestFlight y probar Screen Time sin cambiar mas ajustes antes: si iOS ya tiene el permiso concedido deberia avanzar al paso 2; si no, debe mostrar `Estado iOS: approved/denied/notDetermined`.
- Si `1.0 (2)` sigue mostrando pendiente aunque Ajustes mantenga Blank activado, revisar en el propio iPhone el valor mostrado por `Estado iOS: ...` y usarlo como siguiente diagnostico.
- Para pruebas externas, preparar la informacion de beta review si se quiere invitar a testers fuera del equipo.
- En la proxima sesion, leer este archivo antes de tocar el repo.

## Decisiones
- [cerrada] 2026-07-09: Para iOS, la rama operativa de compilacion en MacinCloud es `codex/ios-device-activity-target`.
- [cerrada] 2026-07-09: El Team ID de Apple para el proyecto iOS es `GS54UV79RG`.
- [cerrada] 2026-07-09: El proyecto usara `ESTADO.md` en la raiz como fuente de verdad incremental para continuidad entre sesiones.
- [cerrada] 2026-07-09: Las instrucciones de gestion de estado viven en `AGENTS.md` para que los agentes las encuentren al abrir el repo.

## Descartado
- 2026-07-09: No se considera bloqueado por Swift/proyecto porque el build de simulador sin firma en Xcode 26.5 termino con `BUILD SUCCEEDED`.
- 2026-07-09: No se podia completar archive/TestFlight porque faltaba provisioning valido y seguia pendiente la aprobacion de `Family Controls (Distribution)`.
- 2026-07-09: No se anadio la regla solo al `README.md` porque es una instruccion operativa para agentes, no documentacion de producto.
- 2026-07-09: Se descarta seguir repitiendo `Automatically manage signing` + `Download Manual Profiles` + `Clean Build Folder` como solucion unica porque el archive mantiene el fallo de `.mobileprovision` inexistente para la extension.

## Notas para la proxima sesion
- Si se retoma iOS en MacinCloud, abrir `~/BlankMVP/ios/Blank/Blank.xcodeproj` y revisar Signing & Capabilities de los targets `Blank` y `BlankDeviceActivityMonitor`.
- No perder el cambio manual actual: la extension debe usar `Blank Device Activity Monitor Development iPhone Guillem` si Xcode vuelve a fallar con un `.mobileprovision` generado automaticamente.
- Si Xcode vuelve a mostrar `No Accounts`, revisar Apple Accounts; la cuenta usada fue `guillemarcos23@gmail.com`.
- No asumir que TestFlight esta listo solo por tener aprobado `Family Controls (Distribution)`: falta configurar managed capabilities, perfiles de distribucion y validar archive/subida.
- Mantener las actualizaciones de este archivo pequenas e incrementales.
- No reabrir decisiones marcadas como `[cerrada]` salvo peticion explicita del usuario.
- Para Screen Time, no sacar conclusiones del build `1.0 (1)`; la siguiente prueba valida es TestFlight `1.0 (2)`.
