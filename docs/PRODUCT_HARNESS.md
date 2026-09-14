# Product Construction Harness

`product-harness-v1` es la capa de construcción de Blankmind. El `bm-harness` observa y limita la ejecución de BM en runtime. Este harness coordina cómo se implementan, validan y cierran cambios de producto.

## Flujo

`objetivo → contrato → contexto mínimo → implementación → validación → reparación acotada → revisión → memoria`

El harness no sustituye al agente que edita el código. Le entrega un contrato ejecutable y convierte el resultado en evidencia reproducible.

## Contrato

Cada trabajo se define en JSON con:

- `objective`: resultado que debe conseguirse;
- `scope`: rutas permitidas;
- `acceptance`: criterios de terminado;
- `context`: proceso y archivos relevantes;
- `validation.commands`: checks obligatorios;
- `validation.repair_commands`: reparaciones opcionales y allowlisted;
- `memory_updates`: líneas exactas que se pueden añadir al cerrar.

El contrato de referencia está en `tools/product_harness_contract.json`.

## Modos

```powershell
node tools/product_harness.js --contract tools/product_harness_contract.json --mode plan
node tools/product_harness.js --contract tools/product_harness_contract.json --mode validate
node tools/product_harness.js --contract tools/product_harness_contract.json --mode close --apply-memory
```

Para medir el alcance desde un punto limpio de trabajo, guardar primero una línea base:

```powershell
node tools/product_harness.js --contract tools/product_harness_contract.json --write-baseline tmp/product-harness/baseline.json --mode plan
node tools/product_harness.js --contract tools/product_harness_contract.json --baseline tmp/product-harness/baseline.json --enforce-scope --mode validate
```

`plan` carga y comprueba el contexto sin ejecutar validaciones. `validate` ejecuta los checks y genera un informe JSON en `tmp/product-harness/`. `close` hace lo mismo y, con `--apply-memory`, añade únicamente las actualizaciones declaradas en el contrato.

## Seguridad y autonomía

Por defecto, el harness bloquea despliegues, publicación, `git reset/checkout/clean/push`, borrados, migraciones destructivas y operadores de shell. Las reparaciones tienen un máximo de tres intentos y solo pueden usar comandos allowlisted.

La autonomía queda dividida así:

- automática: contexto, edición, tests, smoke tests, evals, reparaciones seguras e informe;
- con revisión: cambios fuera de `scope`, migraciones, deploys, Store/TestFlight, pagos, secretos y acciones destructivas.

## Evidencia y métricas

Cada ejecución genera `run_id`, hash del contrato/contexto, comandos, duración, salida redactada, reparaciones, estado de alcance y estado final. Las métricas útiles son tiempo hasta verde, porcentaje al primer intento, reparaciones por tarea, intervenciones humanas, regresiones y coste.

No persiste prompts completos ni conversaciones privadas. La memoria se actualiza solo si el contrato declara el texto exacto y la ejecución termina correctamente.
