# Blank: utilidad visible

## Idea central

Blank es el espacio que queda cuando se retira lo que distrae. La marca demuestra esa idea con una interfaz que solo contiene información, decisiones y controles necesarios. Cada pantalla debe permitir entender el estado actual y ejecutar el siguiente paso.

## Reglas visuales

- Fondo blanco o superficie neutra del sistema; texto carbón con contraste accesible. En protección activa, invertir estos valores sin añadir efectos.
- Inter para la voz tipográfica de la app. Jerarquía mediante tamaño, peso y espacio; no mediante colores de adorno.
- Separadores solo para agrupar acciones o estados. Controles nativos cuando intervienen permisos, selección de apps, teléfono o notificaciones.
- Sin ilustraciones, confeti, brillo, degradados, vidrio, sombras ornamentales ni tarjetas que no agrupen una función real.
- Los iconos solo identifican una acción o estado que no resulte igual de claro con texto. El color de alerta se reserva para un error real.

## Voz y producto

- Títulos con verbos o estados concretos: «Link your iPhone», «Prepare this iPhone», «Connect WhatsApp».
- No prometer protección hasta verificar permiso de Tiempo de uso, selección, notificaciones, vínculo del canal y registro del dispositivo.
- No pedir datos que Blankmind pueda obtener en una conversación natural. El alta solicita solo identidad, consentimiento, capacidades del iPhone y canal.
- No simular personalización, métricas o progreso. Mostrar «Ready» únicamente cuando el sistema lo haya confirmado.

## Recorrido inicial iOS

1. **Link your iPhone:** teléfono, consentimiento explícito, SMS de un solo uso y verificación.
2. **Prepare this iPhone:** permiso de Tiempo de uso, una lista reutilizable de apps y webs, y notificaciones. Cada fila muestra estado y acción.
3. **Connect WhatsApp:** mensaje `CONNECT` preparado para el número verificado. Al volver, Blank confirma vínculo, token APNs, sincronización y disponibilidad antes de abrir la app.

Nombre, edad, objetivos y hábitos se captan en WhatsApp con conversación natural. SMS se ofrecerá como canal conversacional cuando su transporte BM Final esté validado. El primer bloqueo solo ocurre tras una petición del usuario.
