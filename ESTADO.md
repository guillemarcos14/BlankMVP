# Estado del proyecto

Ultima actualizacion: 2026-07-13

## Resumen actual
- BlankMVP es un proyecto para Blank, un bloqueador de apps controlado por NFC.
- El repo contiene app Android (`app/`), MVP iPhone (`ios/Blank/`), documentos de lanzamiento (`docs/`) y landing estatica (`web/landing/`).
- Este archivo es la fuente de verdad operativa para continuidad entre sesiones.

## Hecho hoy
- 2026-07-13: En MacinCloud se trajo el commit `466c820`, se verifico `xcrun agvtool what-version -terse = 7` y se dejo el arbol tracked limpio; solo quedan `xcsuserdata` no versionados de Xcode.
- 2026-07-13: En MacinCloud se trajo `acc7856`, se compilo con `xcodebuild` para simulador con `BUILD SUCCEEDED`, se instalo el `.app` generado y se lanzo en iPhone 17; visualmente se ven modos, ajustes, textura y frase principal con ancho controlado.
- 2026-07-13: Tras captura del simulador donde la Home quedaba demasiado baja, se separo el layout en tres capas: bloque superior anclado arriba, frase principal posicionada por altura de pantalla y CTA anclado abajo, para que los avisos no empujen la composicion.
- 2026-07-13: Tras nueva captura del simulador, se subio el CTA inferior fijando un margen minimo de 52 pt frente al borde inferior para que no quede cortado cuando `safeAreaInsets.bottom` no protege suficiente.
- 2026-07-13: Se corrigio la regla estructural de la Home: la frase principal queda en el centro exacto de pantalla (`height / 2`) y el bloque superior usa una banda estable basada en safe area (`48...72 pt`) para modos, ajustes y avisos.
- 2026-07-13: Se corrigio el layout responsive de la Home iOS para que modos, ajustes, frase principal y CTA usen margenes calculados desde `safeAreaInsets` y ancho real del dispositivo, evitando posiciones pegadas a bordes en iPhone 12 frente a simuladores grandes.
- 2026-07-13: Tras captura de TestFlight `1.0 (6)` donde el CTA ya estaba corregido pero no se veian textura, modos ni ajustes, se bajo la top bar a una posicion visible bajo la zona de estado/TestFlight, se reforzo la textura del fondo con una capa procedural, se preparo el siguiente build como `1.0 (7)` y se corrigio `CFBundleVersion` de la app principal para usar `$(CURRENT_PROJECT_VERSION)`.
- 2026-07-13: En MacinCloud se ejecuto desde Terminal tecla a tecla `xcrun agvtool new-version -all 6` en `~/BlankMVP/ios/Blank`; `xcrun agvtool what-version -terse` devolvio `6`.
- 2026-07-13: Tras comprobar en Organizer que ya existian archives `1.0 (5)`, se decidio que el siguiente archive iOS debe usar build `1.0 (6)`.
- 2026-07-13: Tras `Build Failed` en Xcode por `'self' used in property access 'backgroundThemeId' before all stored properties are initialized`, se corrigio `SessionStore.init` para persistir el tema normalizado usando una constante local antes de terminar la inicializacion.
- 2026-07-13: En MacinCloud se actualizo `~/BlankMVP` desde Terminal tecla a tecla con `git pull --ff-only origin codex/ios-device-activity-target`; quedo en `4690e7e Fix iOS home gray background` y se abrio `ios/Blank/Blank.xcodeproj` en Xcode.
- 2026-07-13: Se reviso la Home iOS tras nueva captura del iPhone: el tema `grey` no correspondia con los assets reales `bg_gray_1/bg_gray_2`, por lo que SwiftUI no cargaba la textura; se normalizo a `gray`, se migra el valor antiguo y se oculto explicitamente la navigation bar en `HomeView`.
- 2026-07-13: Se limito el CTA principal de iOS dentro de `BlankPrimaryButtonStyle` para que no dependa solo del contenedor externo y no pueda renderizar como barra de borde a borde.
- 2026-07-12: Se aclaro el flujo para cambiar nombre e icono en App Store Connect: el nombre visible en la ficha se edita en la version/localizacion editable y el icono requiere cambiar assets en Xcode y subir una nueva version/build para revision.
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
- 2026-07-11: En MacinCloud/Xcode, `Product > Archive` para `Blank 1.0 (2)` completo con `Build Succeeded` y aparece en Organizer; quedan dos warnings visibles (`Switch must be exhaustive` y falta `AccentColor`) que no bloquean la distribucion.
- 2026-07-11: El usuario completo `Distribute App` -> `App Store Connect` -> `Upload` para `Blank 1.0 (2)` y Xcode termino con `Done`; queda esperar procesamiento en App Store Connect/TestFlight y actualizar en el iPhone.
- 2026-07-12: El usuario confirma que `Blank 1.0 (2)` no aparecia en TestFlight porque faltaba informacion de exportacion en App Store Connect; esa informacion ya esta resuelta.
- 2026-07-12: Tras probar la app descargada en iPhone, se corrigio en iOS la paridad visual con Android: fuentes `Instrument Serif` e `Inter`, fondos Android copiados al asset catalog y eliminacion del degradado negro/rojo en modo activo.
- 2026-07-12: En iOS, los avisos de configuracion y el mensaje `Sin apps seleccionadas` pasan a ser accionables: Screen Time reintenta autorizacion, NFC abre vinculacion y apps abre el selector.
- 2026-07-12: En iOS, el horario diario cambia de campos de texto a rueda `DatePicker` estilo iPhone para inicio y fin.
- 2026-07-12: En iOS, si el horario diario esta activo y se escanea el NFC durante una ventana programada, Blank pausa el bloqueo 5 minutos, limpia los shields y luego deja que el horario vuelva a bloquear al expirar la pausa.
- 2026-07-12: Se subio a GitHub la rama `codex/ios-device-activity-target` con las correcciones iOS de diseno/horario/NFC y se incremento el build iOS local a `1.0 (3)` para la siguiente subida a TestFlight.
- 2026-07-12: Se anadio soporte `DEBUG` para iterar estetica con SwiftUI Previews de `HomeView`: home normal, fondo mint, sin apps, NFC pendiente, Blank activo, timer, horario pausado y permiso pendiente.
- 2026-07-12: Se anadio el scheme compartido `Blank.xcscheme` al proyecto iOS para que Xcode muestre el target principal `Blank` en el selector de schemes y pueda compilar previews.
- 2026-07-12: Se sustituyo el `PreviewProvider` de `HomeView` por macros explicitas `#Preview(...)` para que Xcode detecte mejor las variantes visuales en Canvas.
- 2026-07-12: En MacinCloud se ejecuto desde Terminal el `git pull --ff-only origin codex/ios-device-activity-target` y se abrio `ios/Blank/Blank.xcodeproj` de nuevo.
- 2026-07-12: Se anadio en iOS un acceso `DEBUG` exclusivo de simulador para entrar al Home sin NFC real y revisar la estetica del proyecto actual ejecutandose como app.
- 2026-07-12: En iOS `HomeView` se limpio la home eliminando el contador de selecciones protegidas y los mensajes de activacion/desactivacion, se puso el contador activo con `Instrument Serif`, se suavizo el cambio visual entre estados con crossfade de fondos y se cambio Emergencia a una confirmacion explicativa.
- 2026-07-12: Se subio a GitHub `codex/ios-device-activity-target` con los ultimos cambios de `HomeView` para que MacinCloud pueda hacer pull y generar/subir `Blank 1.0 (3)` al iPhone via TestFlight.
- 2026-07-12: En MacinCloud, desde Terminal, se ejecuto `git status`, `git pull --ff-only origin codex/ios-device-activity-target` y `open ios/Blank/Blank.xcodeproj`; el pull hizo fast-forward e incorporo `ESTADO.md` y `HomeView.swift`.
- 2026-07-12: En MacinCloud se comprobo por Terminal que `ios/Blank/Blank.xcodeproj/project.pbxproj` ya tiene `CURRENT_PROJECT_VERSION = 4` en las cuatro entradas; Organizer seguia mostrando archives `1.0 (3)` porque eran archives anteriores o generados antes de tomar ese cambio.
- 2026-07-12: Se resolvio el archive que seguia saliendo como `1.0 (3)`: se cerro Xcode en MacinCloud, se ejecuto `xcrun agvtool new-version -all 4` desde `ios/Blank`, se limpio DerivedData, se reabrio `Blank.xcodeproj`, se hizo `Product > Clean Build Folder` y el nuevo archive aparece en Organizer como `1.0 (4)`.
- 2026-07-12: Tras captura del iPhone donde la Home con fondo Grey no mostraba modo/ajustes, dejaba la barra de estado blanca y el CTA parecia una barra cuadrada, se quito el esquema oscuro global y se fijo contraste, anchura y padding de `HomeView`.

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
- La app iOS ya tiene cambios locales para corregir diseno y friccion antes de produccion real; falta compilar/probar en MacinCloud/Xcode y subir un nuevo build si pasa.
- Para iteracion estetica rapida, `HomeView.swift` ya incluye una galeria de SwiftUI Previews con datos aislados de `UserDefaults` para no depender de TestFlight ni de tokens reales de FamilyControls.
- Xcode debe usar el scheme `Blank`, no `BlankDeviceActivityMonitor`, para compilar previews de `HomeView`.
- La home iOS ya tiene el ajuste solicitado de textos, contador, transicion visual y confirmacion de emergencia; en Windows solo se hizo validacion estatica (`git diff --check`) porque no hay toolchain Swift local.
- La rama remota `codex/ios-device-activity-target` ya contiene la version iOS preparada para compilar y subir como `1.0 (3)`.
- En MacinCloud, Xcode queda abierto en `~/BlankMVP/ios/Blank/Blank.xcodeproj` con el scheme `Blank` y destino `Any iOS Device (arm64)` tras el pull de los ultimos cambios.
- En MacinCloud el siguiente build/archive iOS debe quedar en `1.0 (7)` porque `1.0 (6)` ya se uso para validar la captura actual.
- El arreglo visual de la Home Grey/Gray ahora corrige el fallo de nombre de asset (`grey` -> `gray`) y se ha validado solo de forma estatica en Windows (`git diff --check`); falta compilar/probar en Xcode o TestFlight para confirmar el resultado real en iPhone.
- La Home iOS ya no depende de paddings absolutos ni de `Spacer()` simetricos para top bar/frase/CTA; la frase queda centrada por pantalla y el bloque superior esta acotado por safe area; falta compilar y revisar el ultimo ajuste en MacinCloud antes de otro TestFlight.

## Proximos pasos concretos
- Confirmar si el build con `0 errores` fue `Product > Build` para `Any iOS Device (arm64)` y guardar captura/nota del resultado.
- Si se quiere instalar en iPhone fisico, seleccionar el dispositivo registrado y ejecutar build/run de desarrollo.
- No repetir solo el toggle de `Automatically manage signing`; ya se probo en `Release` con `Clean Build Folder` y el error persistio.
- Resolver el archivo de provisioning de archive para `com.blanknfc.app.ios.deviceactivity` o esperar aprobacion de `Family Controls (Distribution)` antes de insistir con TestFlight/App Store.
- Cuando TestFlight muestre `Blank 1.0 (2)`, actualizar la app en el iPhone.
- En el iPhone, instalar `Blank 1.0 (2)` desde TestFlight y probar Screen Time sin cambiar mas ajustes antes: si iOS ya tiene el permiso concedido deberia avanzar al paso 2; si no, debe mostrar `Estado iOS: approved/denied/notDetermined`.
- Si `1.0 (2)` sigue mostrando pendiente aunque Ajustes mantenga Blank activado, revisar en el propio iPhone el valor mostrado por `Estado iOS: ...` y usarlo como siguiente diagnostico.
- Para pruebas externas, preparar la informacion de beta review si se quiere invitar a testers fuera del equipo.
- En MacinCloud/Xcode, compilar el proyecto iOS tras estos cambios y verificar en iPhone: fuentes reales, fondos por variante, mensaje accionable, horario con rueda y pausa NFC de 5 minutos durante horario activo.
- En Xcode, usar Canvas/Previews sobre `HomeView.swift` para ajustar estetica antes de hacer otro build real.
- En MacinCloud/Xcode, compilar y revisar `HomeView` en simulador/previews para validar visualmente la transicion smooth y la hoja de Emergencia.
- En Xcode, revisar visualmente `HomeView` o ejecutar `Product > Archive` para generar un nuevo archive con el arreglo de Home y build `1.0 (7)`.
- Antes de subir otro build, revisar la Home Gray en Xcode/simulador o iPhone: barra de estado oscura, modo visible, ajustes pulsable, textura `bg_gray_*` cargada y CTA redondeado con margen lateral.
- En MacinCloud, probar la Home con un simulador cercano al iPhone 12 ademas del iPhone 17 para confirmar que safe area, CTA y frase principal mantienen distancia visual suficiente.
- En la proxima sesion, leer este archivo antes de tocar el repo.

## Decisiones
- [cerrada] 2026-07-09: Para iOS, la rama operativa de compilacion en MacinCloud es `codex/ios-device-activity-target`.
- [cerrada] 2026-07-09: El Team ID de Apple para el proyecto iOS es `GS54UV79RG`.
- [cerrada] 2026-07-09: El proyecto usara `ESTADO.md` en la raiz como fuente de verdad incremental para continuidad entre sesiones.
- [cerrada] 2026-07-09: Las instrucciones de gestion de estado viven en `AGENTS.md` para que los agentes las encuentren al abrir el repo.
- [cerrada] 2026-07-12: La app iOS debe usar `Instrument Serif` e `Inter` como Android y tomar sus fondos desde los assets Android, no desde degradados aproximados.
- [cerrada] 2026-07-12: Durante un horario diario activo, escanear el NFC debe dar 5 minutos de desbloqueo temporal y despues permitir que el horario vuelva a aplicar el bloqueo.
- [cerrada] 2026-07-12: La iteracion estetica iOS se hara primero con SwiftUI Previews y simulador; TestFlight queda para validar NFC, Screen Time, firma y comportamiento real.
- [cerrada] 2026-07-12: El bypass para entrar al Home sin NFC solo puede existir en `DEBUG` y `targetEnvironment(simulator)`, nunca en TestFlight ni produccion.

## Descartado
- 2026-07-09: No se considera bloqueado por Swift/proyecto porque el build de simulador sin firma en Xcode 26.5 termino con `BUILD SUCCEEDED`.
- 2026-07-09: No se podia completar archive/TestFlight porque faltaba provisioning valido y seguia pendiente la aprobacion de `Family Controls (Distribution)`.
- 2026-07-09: No se anadio la regla solo al `README.md` porque es una instruccion operativa para agentes, no documentacion de producto.
- 2026-07-09: Se descarta seguir repitiendo `Automatically manage signing` + `Download Manual Profiles` + `Clean Build Folder` como solucion unica porque el archive mantiene el fallo de `.mobileprovision` inexistente para la extension.

## Notas para la proxima sesion
- Si se cambia logo o nombre de App Store, distinguir entre metadata de App Store Connect, nombre instalado (`CFBundleDisplayName`) e icono empaquetado en el build.
- Si se retoma iOS en MacinCloud, abrir `~/BlankMVP/ios/Blank/Blank.xcodeproj` y revisar Signing & Capabilities de los targets `Blank` y `BlankDeviceActivityMonitor`.
- No perder el cambio manual actual: la extension debe usar `Blank Device Activity Monitor Development iPhone Guillem` si Xcode vuelve a fallar con un `.mobileprovision` generado automaticamente.
- Si Xcode vuelve a mostrar `No Accounts`, revisar Apple Accounts; la cuenta usada fue `guillemarcos23@gmail.com`.
- No asumir que TestFlight esta listo solo por tener aprobado `Family Controls (Distribution)`: falta configurar managed capabilities, perfiles de distribucion y validar archive/subida.
- Mantener las actualizaciones de este archivo pequenas e incrementales.
- No reabrir decisiones marcadas como `[cerrada]` salvo peticion explicita del usuario.
- Para Screen Time, no sacar conclusiones del build `1.0 (1)`; la siguiente prueba valida es TestFlight `1.0 (2)`.
