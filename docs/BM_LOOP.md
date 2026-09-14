# BM Loop Engineering

`bm-loop-excellence-v1` controla el ciclo temporal de una recomendación. No ejecuta acciones del dispositivo y no sustituye a `actionGate`.

## Contrato runtime

La función `/.netlify/functions/bm-loop` acepta `operation=start` y `operation=advance`. El contrato vive en `netlify/functions/bm-loop-contract.json` y exige versión, identidad, hipótesis, intervención, criterios de éxito, consentimiento, presupuesto, fingerprint, estado, secuencia de eventos, verificación y stop conditions.

El estado público no expone prompts ni el array interno `events`: transporta únicamente `event_history` seguro, hashes y metadatos necesarios para que iOS/Android puedan reanudar el loop sin perder orden ni idempotencia.

Estados: `awaiting_input`, `awaiting_setup`, `awaiting_confirmation`, `awaiting_execution`, `retryable`, `completed`, `stopped` y `failed`.

Eventos: `confirm`, `setup_completed`, `execution_started`, `executed`, `verified`, `outcome_recorded`, `declined`, `cancelled` y `failed`.

## Invariantes

- `executed` exige `execution_started` en la iteración actual.
- Un loop con acción no termina sin verificación positiva.
- El mismo `event_id` es idempotente. Si cambia su payload, se rechaza.
- Acciones desconocidas fallan cerrado.
- Hay límites de 3 iteraciones, 32 eventos, 4 acciones y 168 horas.
- Tras un estado terminal solo se permite registrar el outcome.
- El resultado de la app sigue siendo la autoridad de verdad.

## Persistencia y privacidad

La migración `012_bm_loop_engineering.sql` crea estado replayable, eventos, RPC transaccional con bloqueo optimista, RLS y una vista agregada de aprendizaje. La función solo persiste con `data_consent=true` y guarda el identificador hasheado. Si Supabase no está configurado, el loop sigue funcionando sin persistencia. Un conflicto de versión debe reintentarse con el estado más reciente. La app sigue siendo la autoridad para declarar la verificación del dispositivo.
