# Backend Cloud: flujo de integración y despliegue

Este flujo reúne cambios hechos en varias conversaciones y los valida/despliega como una sola release.

## Regla central

Las conversaciones de implementación nunca despliegan producción. Cada una trabaja en una rama `codex/...`, hace commit y entrega la rama. La única conversación autorizada para integrar y desplegar es `Integración y deploy Backend Cloud`.

El flujo afecta a:

- Netlify Functions de `netlify/functions/`.
- Migraciones y Edge Functions de `supabase/`.
- Tests, harness y documentación técnica relacionados.

La compilación iOS/Android continúa siendo un flujo separado.

## Ciclo reusable

1. Implementar cada resultado en una rama independiente y hacer commit.
2. En la conversación de integración, revisar las ramas:

   ```powershell
   node tools/backend_release.js --mode plan --base main `
     --branch codex/backend/persistencia-contexto `
     --branch codex/backend/bm-app `
     --branch codex/backend/codigos
   ```

3. Crear la rama de release y fusionar:

   ```powershell
   node tools/backend_release.js --mode integrate --base main `
     --name codex/backend-release-2026-09-15 `
     --branch codex/backend/persistencia-contexto `
     --branch codex/backend/bm-app `
     --branch codex/backend/codigos
   ```

   El comando se detiene si el árbol tiene cambios sin commit o si aparece un conflicto.

4. Crear la línea base de esta release:

   ```powershell
   node tools/product_harness.js --contract tools/product_harness_contract.json `
     --write-baseline tmp/product-harness/baseline.json --mode plan
   ```

5. Validar una sola vez todo el backend:

   ```powershell
   node tools/backend_release.js --mode validate
   ```

   Para la suite amplia con modelo real:

   ```powershell
   node tools/backend_release.js --mode validate --full
   ```

6. Desplegar explícitamente los targets necesarios:

   ```powershell
   node tools/backend_release.js --mode deploy --confirm --supabase --netlify
   ```

   `--supabase` aplica migraciones y publica `digital-wellness-features`. `--netlify` publica `getblank` y sus Functions. Sin `--confirm`, el comando no muta servicios externos.

## Contrato de entrega de cada conversación

Antes de pasar una rama a integración, la conversación debe indicar:

- rama y commit final;
- objetivo y archivos modificados;
- migraciones nuevas y orden requerido;
- variables de entorno nuevas o cambiadas;
- validaciones ejecutadas y resultado;
- riesgos, conflictos o pruebas físicas pendientes.

Una rama que mezcle cambios de app con backend debe avisarlo en la entrega. La herramienta lo marca para revisión.

## Evidencia

La herramienta guarda informes locales en `tmp/backend-release/`. Son artefactos operativos y no deben convertirse en código ni memoria de producto.

No se considera publicado un cambio hasta tener:

- `Backend validation passed` en la rama de release;
- migraciones aplicadas si existen;
- deploy Netlify confirmado si se modificaron Functions;
- smoke remoto posterior cuando el cambio afecte a contratos BM, identidad, memoria o loops.
