# BM Product Engineering Excellence

Este documento define cómo BM construye producto con contratos ejecutables, ciclos verificables y aprendizaje controlado. Las versiones `excellence-v1` son contratos estables de producción, no prototipos descartables.

## Flujo completo

```text
context → planner → action contract → policy → confirmation/autonomy
        → device execution → verification → outcome → adaptation
        → durable trace → evaluation → release gate
```

## 3. Tool/Action + Contract Engineering

`bm-contracts.js` normaliza acciones, limita el número de acciones, valida tipos permitidos, genera fingerprints estables y conserva los campos nullable que necesitan iOS y Android. Una acción desconocida falla cerrada.

El loop y las plataformas comparten `action_types`, `plan_fingerprint`, `state_version` y eventos versionados. Esto evita que cada cliente interprete el plan de manera distinta.

## 4. State + Memory Engineering

`bm-loop.js` es una máquina de estados explícita. `bm-context.js` limita el contexto que llega al planner a señales, memoria estructurada y conversación reciente acotada. Nunca se guarda `last_prompt` ni se envía contexto ilimitado.

La memoria operativa y el estado de ejecución son objetos distintos: la memoria describe al usuario; el loop describe una intervención concreta.

## 5. Verification + Recovery Engineering

`bm-verification.js` acepta evidencia resumida y exige `success=true` más `verification=passed` para completar una acción. `executed` sin verificación positiva deja el loop en fase `verify`.

Los fallos pasan a `retryable`, incrementan el presupuesto de iteración y generan una señal de adaptación. Al agotar el presupuesto, el loop se detiene con `verification_failed_after_budget`.

## 6. Evaluation + Simulation Engineering

`tools/bm_excellence_gate.js` prueba contratos, privacidad, política, replay, verificación, aprendizaje, paridad nativa, persistencia y smoke tests. `bai_release_gate.js` lo ejecuta antes de release.

Los fallos deben promoverse desde simulaciones o pruebas reales a regresiones permanentes. El gate no evalúa solo texto: también evalúa estado final, transición y evidencia.

## 7. Observability + Reliability Engineering

El harness registra `run_id`, `trace_id`, hashes, etapas, duración, fuente, acciones y warnings sin exponer prompts. El loop mantiene `state_version`, `event_sequence`, fingerprints de eventos y `last_rejection`.

La persistencia usa `bm_append_loop_event`, bloqueo de fila, control optimista de versión y unicidad `(loop_id, event_id)`. Repetir un evento es seguro; reutilizar un `event_id` con otro payload se rechaza.

## 8. Safety + Autonomy Engineering

`bm-policy.js` asigna riesgo por acción. Por defecto, las acciones requieren confirmación. Solo una rutina con consentimiento explícito, tipo autorizado y dispositivo listo puede entrar en ejecución autónoma.

El modelo nunca ejecuta directamente: propone; la política y la aplicación autorizan; el dispositivo ejecuta; la verificación decide si el resultado es válido.

## 9. Outcome + Feedback + Experimentation Engineering

`bm-learning.js` normaliza outcomes (`held`, `broke`, `improved`, `relapse`, `failed`, etc.) y produce señales de adaptación sin guardar texto privado. La migración `012_bm_loop_engineering.sql` mantiene el ledger durable y la vista agregada de aprendizaje.

Las recomendaciones futuras deben usar outcomes verificados y feedback explícito, no volumen sintético ni cambios automáticos no auditados.

## 10. Device, Integration, Release y Privacy Engineering

iOS y Android reportan el mismo ciclo `execution_started → executed → verified` y registran el outcome junto al `loop_id`. La app sigue siendo autoridad de permisos y estado del dispositivo.

El gate comprueba paridad de eventos, contratos de integración y RLS. Los deploys, migraciones, secretos, builds firmadas y acciones destructivas siguen fuera de la autonomía automática del product harness.

## Gates obligatorios

```powershell
node tools/bm_excellence_gate.js
node tools/product_harness.js --contract tools/product_harness_contract.json --baseline tmp/product-harness/baseline.json --mode validate --enforce-scope
```

Un cambio solo está listo cuando ambos producen resultado `passed` y la evidencia queda guardada en `tmp/reports/`.
