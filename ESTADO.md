# Estado del proyecto

Ultima actualizacion: 2026-07-29

## Resumen actual
- BlankMVP es el repositorio de Blank, un bloqueador de apps controlado por NFC.
- El producto combina una app Android, una app iOS y una landing/web de validacion comercial.
- La vision actual es convertir Blank en un dispositivo fisico de foco digital: tocar un tag NFC para activar/desactivar bloqueo de apps distractoras, creando friccion real sin depender solo de fuerza de voluntad.
- Este archivo debe leerse siempre antes de cualquier peticion, accion, analisis, cambio de codigo, gestion de GitHub, compilacion, decision de producto o respuesta sustantiva sobre el proyecto.
- `ESTADO.md` es la fuente de verdad operativa del proyecto.

## Estado de GitHub
- `main` contiene ahora este archivo para que Codex pueda acceder al contexto desde la rama por defecto.
- La rama historica/operativa `codex/ios-device-activity-target` contiene una version mucho mas larga de `ESTADO.md` con el diario completo de trabajo anterior.
- El intento de integrar toda la rama `codex/ios-device-activity-target` en `main` mediante PR encontro conflictos por la migracion iOS `ios/Brick` -> `ios/Blank`, por lo que no debe mergearse a ciegas.

## Estado de producto
- Android: MVP en Kotlin/Jetpack Compose. Ya hay trabajo avanzado de bloqueo por accesibilidad, seleccion de apps, NFC, progreso, horario y release beta/Play Console.
- iOS: MVP en SwiftUI usando Core NFC y Screen Time APIs (`FamilyControls`, `ManagedSettings`, `DeviceActivity`). La ruta actual de proyecto es `ios/Blank/Blank.xcodeproj`.
- Landing/web: `web/landing/` y preview web se usan para validacion comercial, waitlist/preorder y soporte de App Review.
- Comercial: foco inmediato en ventas, revision Android, App Review iOS, soporte inicial, prueba social y medicion de conversion.

## Hecho hoy
- 2026-07-28: Se comprobo que `ESTADO.md` no estaba en `main`, pero si en la rama `codex/ios-device-activity-target`.
- 2026-07-28: Se creo la PR #3 (`Sync Blank project state and app updates`) desde `codex/ios-device-activity-target` a `main`; GitHub marco conflictos.
- 2026-07-28: Se resolvio parcialmente el conflicto Android de `app/build.gradle.kts` en la rama de la PR manteniendo `compileSdk = 36`, `targetSdk = 36` y `versionCode = 21`.
- 2026-07-28: Se detectaron conflictos restantes por rutas antiguas `ios/Brick/Brick/*` frente a la migracion activa `ios/Blank/*`.
- 2026-07-28: Para evitar un merge grande y arriesgado, se sube a `main` un estado operativo compacto y `AGENTS.md` sin arrastrar los 101 archivos de la rama conflictiva.
- 2026-07-28: Se reforzo la regla operativa: ante cualquier peticion o accion sobre este proyecto, consultar siempre antes `ESTADO.md` como fuente de verdad.
- 2026-07-28: Se aplico en `web/landing/index.html` un nuevo override `web/landing/home-background.css` para cambiar el fondo de la hero/home por un fade suave azul-gris-beige alineado con la direccion visual de Blank App.
- 2026-07-29: Se autentico GitHub CLI (`gh`) como `guillemarcos14`, se conecto `git` al credential helper de `gh` y se reemplazo la copia recuperada por ZIP por un clon real en `/Users/andreaalejo21/Documents/Blank`.
- 2026-07-29: Se intento inicialmente integrar completa la rama buena `origin/codex/ios-device-activity-target` en una rama local de integracion, pero se descarto ese merge completo al confirmar que trae cambios funcionales amplios. Por instruccion del usuario, se porto solo la estetica/posicion de Home: frase fija `¿Lo ves? Al final / no era urgente, / era costumbre.`, fondos visuales de Home y CTA compacto `Blankear`, sin cambiar flujos de NFC, permisos, bloqueo, seleccion de apps ni sesion.

## Estado actual
- `ESTADO.md` existe en `main` como fuente de contexto compacta.
- `/Users/andreaalejo21/Documents/Blank` es ahora un clon Git real de `guillemarcos14/BlankMVP` en `main`; `git fetch` funciona desde terminal.
- Para historia completa, consultar `ESTADO.md` en `codex/ios-device-activity-target`.
- No considerar mergeada la rama grande hasta resolver conscientemente la migracion `ios/Brick` -> `ios/Blank` y revisar los cambios de Android/iOS/assets.
- La home de `web/landing/` carga `home-background.css` despues de `styles.css` para aplicar el nuevo fondo sin tocar el stylesheet principal.
- La integracion solicitada hacia `main` debe mantenerse acotada a estetica/posicion mientras el usuario no autorice cambios funcionales o migraciones estructurales.

## Proximos pasos concretos
- Usar `main` para recuperar contexto minimo desde cualquier PC o nueva sesion Codex.
- Si se quiere integrar todo el trabajo de `codex/ios-device-activity-target`, hacerlo en una rama dedicada con merge local, resolviendo explicitamente los conflictos iOS y validando Android/iOS.
- Mantener `compileSdk = 36`, `targetSdk = 36` y `versionCode = 21` o superior en Android; no retroceder esos valores.
- Para iOS, la rama buena usa `ios/Blank/`, pero `main` conserva todavia `ios/Brick/`; no migrar estructura iOS en pases limitados a estetica/posicion.
- Revisar visualmente la landing desplegada en Netlify cuando termine el redeploy automatico.
- Usar `/Users/andreaalejo21/Documents/Blank` como carpeta local principal del proyecto en nuevas sesiones Codex.
- Validar visualmente Home en Android y iOS; en este Mac no hay Java Runtime ni Xcode completo, por lo que las compilaciones locales quedan pendientes en una maquina con JDK/Xcode.

## Decisiones
- [cerrada] 2026-07-09: El proyecto usa `ESTADO.md` como fuente de verdad incremental para continuidad entre sesiones.
- [cerrada] 2026-07-09: Las instrucciones de gestion de estado viven en `AGENTS.md`.
- [cerrada] 2026-07-09: Para iOS, la rama operativa historica es `codex/ios-device-activity-target`.
- [cerrada] 2026-07-28: No se mergea automaticamente la PR grande conflictiva solo para traer `ESTADO.md`; se sube el estado operativo a `main` de forma acotada.
- [cerrada] 2026-07-28: Ante cualquier peticion, accion, analisis o cambio sobre este proyecto, se consulta primero `ESTADO.md`; es la fuente de verdad operativa.
- [cerrada] 2026-07-28: El cambio visual de fondo de la home web se implementa como override CSS separado para mantenerlo acotado y facil de revertir.
- [cerrada] 2026-07-29: La rama `codex/ios-device-activity-target` contiene la version visual buena de Home, pero no se debe mergear completa a `main` bajo la restriccion actual porque incluye cambios funcionales y estructurales.

## Descartado
- 2026-07-28: Descartado mergear a ciegas la PR #3 porque tiene conflictos de migracion iOS y afecta muchos archivos.
- 2026-07-29: Descartado mergear completa `origin/codex/ios-device-activity-target` en `main` en este pase porque el usuario pidio no romper funcionalidad ni flujos y limitarlo a cambios esteticos o de posicion.

## Notas para la proxima sesion
- Leer este archivo antes de tocar el repo.
- Si hace falta detalle historico, abrir `ESTADO.md` en la rama `codex/ios-device-activity-target`.
- No reabrir decisiones marcadas como `[cerrada]` salvo peticion explicita del usuario.
