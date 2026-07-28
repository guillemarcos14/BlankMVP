# Estado del proyecto

Ultima actualizacion: 2026-07-28

## Resumen actual
- BlankMVP es el repositorio de Blank, un bloqueador de apps controlado por NFC.
- El producto combina una app Android, una app iOS y una landing/web de validacion comercial.
- La vision actual es convertir Blank en un dispositivo fisico de foco digital: tocar un tag NFC para activar/desactivar bloqueo de apps distractoras, creando friccion real sin depender solo de fuerza de voluntad.
- Este archivo debe leerse al inicio de cada sesion para recuperar contexto operativo.

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

## Estado actual
- `ESTADO.md` existe en `main` como fuente de contexto compacta.
- Para historia completa, consultar `ESTADO.md` en `codex/ios-device-activity-target`.
- No considerar mergeada la rama grande hasta resolver conscientemente la migracion `ios/Brick` -> `ios/Blank` y revisar los cambios de Android/iOS/assets.

## Proximos pasos concretos
- Usar `main` para recuperar contexto minimo desde cualquier PC o nueva sesion Codex.
- Si se quiere integrar todo el trabajo de `codex/ios-device-activity-target`, hacerlo en una rama dedicada con merge local, resolviendo explicitamente los conflictos iOS y validando Android/iOS.
- Mantener `compileSdk = 36`, `targetSdk = 36` y `versionCode = 21` o superior en Android; no retroceder esos valores.
- Para iOS, tratar `ios/Blank/` como la ruta actual y `ios/Brick/` como ruta antigua salvo que se compruebe lo contrario.

## Decisiones
- [cerrada] 2026-07-09: El proyecto usa `ESTADO.md` como fuente de verdad incremental para continuidad entre sesiones.
- [cerrada] 2026-07-09: Las instrucciones de gestion de estado viven en `AGENTS.md`.
- [cerrada] 2026-07-09: Para iOS, la rama operativa historica es `codex/ios-device-activity-target`.
- [cerrada] 2026-07-28: No se mergea automaticamente la PR grande conflictiva solo para traer `ESTADO.md`; se sube el estado operativo a `main` de forma acotada.

## Descartado
- 2026-07-28: Descartado mergear a ciegas la PR #3 porque tiene conflictos de migracion iOS y afecta muchos archivos.

## Notas para la proxima sesion
- Leer este archivo antes de tocar el repo.
- Si hace falta detalle historico, abrir `ESTADO.md` en la rama `codex/ios-device-activity-target`.
- No reabrir decisiones marcadas como `[cerrada]` salvo peticion explicita del usuario.
