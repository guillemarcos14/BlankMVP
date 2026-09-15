# BM Harness

Actualización semántica 2026-09-15: el product harness incluye 25 checks. Un resultado verde no certifica comprensión ni release. Ver [auditoría y límites](BM_SEMANTIC_AUDIT.md), [oracle/replay](BM_EVALUATION.md) y [adjudicación del evaluador anterior](BM_LEGACY_GATE_ADJUDICATION.md). Los scores legacy se conservan como diagnósticos y no sustituyen las comprobaciones semánticas, nativas y de persistencia.

BM es el nombre actual de Blankmind. `BAI` solo permanece en nombres técnicos heredados.

## Arquitectura de excelencia

El harness de construcción y el runtime BM trabajan juntos, pero tienen responsabilidades distintas:

`intención → contexto → implementación → validación → evidencia → aprendizaje`

En runtime:

`planificar → aplicar política → confirmar/configurar → ejecutar → verificar → outcome → adaptar o detener`

El modelo propone. El código valida. `actionGate` conserva la autoridad sobre acciones reales. La app ejecuta permisos y cambios de dispositivo. Supabase solo recibe estado mínimo y consentido.

## Controles automáticos

Antes de una tarea técnica nueva se crea una línea base. Al terminar se ejecuta `product_harness` con `--enforce-scope`. El contrato valida contexto, alcance, sintaxis, tests, smoke tests, loop y release gate. En CI, el mismo gate bloquea pull requests con cambios fuera de alcance o regresiones.

Cada ejecución produce evidencia reproducible: `run_id`, `trace_id`, hashes de prompt/contexto/plan, ruta, etapas, acciones, warnings, duración y clase de fallo. Nunca se registra el prompt completo.

## Seguridad y autonomía

- Acciones desconocidas fallan cerrado.
- No hay ejecución autónoma sin consentimiento explícito y grant por acción.
- Las acciones se limitan por iteraciones, eventos, tiempo y número de acciones.
- No se completa un loop sin verificación positiva.
- Eventos duplicados son idempotentes y payloads conflictivos se rechazan.
- El outcome puede alimentar aprendizaje sin permitir que el modelo ejecute directamente.

La persistencia replayable está preparada en la migración `012_bm_loop_engineering.sql`. Solo se activa con consentimiento y guarda el identificador de usuario hasheado. Agents API no es necesaria aquí: añadiría una capa de orquestación antes de que BM tenga tareas multi-herramienta suficientemente estables, sin sustituir estos contratos, permisos ni verificaciones.
