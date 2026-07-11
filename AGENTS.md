# Gestion de estado del proyecto

## Al inicio de cada sesion
1. Lee `ESTADO.md` en la raiz del repo antes de hacer nada.
2. Si no existe, crealo con la estructura definida abajo antes de empezar la tarea.
3. Trata su contenido como la fuente de verdad sobre decisiones ya tomadas:
   no propongas rediscutir decisiones marcadas como cerradas salvo que el usuario lo pida.
4. Para trabajo iOS, comprueba primero el estado de Apple Developer, Xcode/MacinCloud y provisioning anotado en `ESTADO.md` antes de cambiar codigo.

## Durante la sesion
- Si se toma una decision de arquitectura, diseno o producto, anotala en
  `ESTADO.md` -> "Decisiones" en el momento, no al final.
- Si un enfoque se prueba y se descarta, anotalo en "Descartado" con una
  linea explicando por que.
- Separa claramente tres capas de estado: compilacion local/simulador, firma/provisioning, y distribucion TestFlight/App Store.
- No presentes un build firmado o un archive como completado si solo se ha verificado `CODE_SIGNING_ALLOWED=NO`.
- No digas que TestFlight esta listo mientras `Family Controls (Distribution)` siga pendiente de aprobacion por Apple.

## Al final de cada bloque de trabajo
Actualiza `ESTADO.md` siempre, sin que el usuario lo pida, cuando ocurra cualquiera de:
- Has completado la tarea solicitada.
- Detectas que la conversacion es larga y el contexto puede compactarse pronto.
- El usuario dice "cierra", "para aqui", "lo dejamos" o similar.

La actualizacion debe ser incremental: edita el archivo, no lo reescribas entero.
Debe reflejar que se hizo hoy, estado actual y proximos pasos concretos.

## Estructura de `ESTADO.md`
Usa esta estructura base y mantenla estable:

```md
# Estado del proyecto

Ultima actualizacion: YYYY-MM-DD

## Resumen actual
- ...

## Hecho hoy
- YYYY-MM-DD: ...

## Estado actual
- ...

## Proximos pasos concretos
- ...

## Decisiones
- [cerrada] YYYY-MM-DD: ...

## Descartado
- YYYY-MM-DD: ... porque ...

## Notas para la proxima sesion
- ...
```
