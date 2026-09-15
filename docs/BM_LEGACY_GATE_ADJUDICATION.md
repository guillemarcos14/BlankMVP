# Adjudicación de los 52 fallos del gate BM anterior

Fecha: 2026-09-15. Esta revisión **no convierte los 52 fallos en aprobados**. El resultado histórico permanece en 62/114 aprobados y 52/114 fallidos. Entre los fallos hay expectativas que ya eran inseguras, defectos reales y cuestiones de calidad todavía sin resolver.

## Evidencia y alcance

- Resultado original: `tmp/bm-semantic/release-gate.json`, entrada `legacy_diagnostics` → `Legacy compatibility contract eval`, ejecución iniciada a las `2026-09-15T17:41:40.696Z`.
- Evaluador y casos originales: `tools/blanked_agent_eval.js` y `tools/blanked_agent_eval_cases.json`. No se modificaron para esta revisión.
- Captura complementaria de los **52 casos exactos**: `tmp/bm-semantic/legacy-adjudication-replay.json`. Incluye prompt, contexto, expectativa completa, primer error histórico, respuesta, estado, decisión, acción y SHA-256 de los archivos ejecutados. Es un replay local posterior; no se presenta como la respuesta conservada por la ejecución original, que no guardaba los planes fallidos.
- Auditoría de falsos positivos: `tmp/bm-semantic/legacy-false-positives-final.json`. Detectar que el evaluador acepta mutaciones incorrectas no demuestra que todos sus fallos sean falsos negativos.
- Esta adjudicación es una revisión manual de evidencia, no un nuevo conjunto ciego. No se consultó producción ni se atribuyeron estas conversaciones sintéticas a usuarios reales.

## Resultado de la revisión

| Clasificación primaria | Casos | Tratamiento |
|---|---:|---|
| O: expectativa obsoleta; sin defecto semántico concreto demostrado en este turno | 13 | Migrar el assert a estado/decisión; no restaurar valores inventados ni ejecución prematura. La calidad blanda no queda certificada. |
| M: expectativa obsoleta **y** defecto real observable | 28 | Conservar ambos hechos. La retirada de una acción insegura no resuelve pérdida de contexto, contradicción o comprensión. |
| R: defecto real de intención, restricción o capacidad | 7 | Bloqueo abierto. No eximir por el cambio de arquitectura; tampoco restaurar ejecución sin confirmación. |
| U: calidad/contexto sin adjudicación concluyente | 4 | Revisión de naturalidad/contexto pendiente. No contado como aprobado ni como fallo semántico duro demostrado. |
| **Total de fallos revisados** | **52** | **35 con defectos reales observados, 4 pendientes y 13 con expectativa obsoleta sin defecto duro demostrado.** |

Los 62 casos que el evaluador aprobó no se revalidan por esta tabla y no equivalen a 62 aprobados semánticos. El evaluador original también presenta falsos positivos comprobados.

## Por qué el primer error no basta

`assertBlockingContract` trata cualquier booleano `blocking_ready` como un contrato de bloqueo y exige `blocking_data`, incluso en respuestas que ya no contienen una propuesta de bloqueo. Muchos casos se detienen en esa comprobación antes de examinar intención y acciones. Esto explica un error de contrato, pero no disculpa que la respuesta haya perdido una petición de revisión semanal o un nombre de aplicación.

`qualityScore` premia longitud, número de bullets y palabras como `Read`, `Pattern`, `Move`, `Block` o `Start`. `utilityScore` vuelve a premiar estructura y vocabulario. Un fallo de esos contadores no demuestra mala semántica; un acierto tampoco demuestra comprensión. `assertPlan` compara algunas acciones y subsets, pero no exige un estado completo, fuentes por slot, autorización vinculada a la propuesta ni equivalencia entre todas las superficies visibles y la acción. La ejecución principal guarda únicamente el mensaje de la primera excepción para cada fallo.

## Mapeo completo

Cada ID enlaza conceptualmente con `results[].id` en la captura complementaria. Los códigos representan el estado observado **antes de las correcciones posteriores que pueda realizar la integración**; solo una nueva evidencia puede cerrar un defecto.

| # | ID original | Clase | Evidencia y conclusión |
|---:|---|:---:|---|
| 1 | `social_lunch_with_memory_creates_specific_window` | M | Esperaba activar un modo `Social` no demostrado y sin confirmación. Ahora no actúa, pero descarta contexto y devuelve estado `general/idle` con decisión `ask/apps`: estado y siguiente paso discrepan. |
| 2 | `night_scroll_missing_bedtime` | U | No hay acción; conserva `advice` y `at night`, pregunta inicio del scrolling. Falla por no contener bed/phone/tired/asleep/offline. La preferencia entre pedir bedtime o comienzo del scrolling requiere evaluación de utilidad, no un regex. |
| 3 | `night_scroll_remembered_bedtime` | U | Igual que #2 y además no utiliza memoria sin procedencia para autorizar. Falta decidir y comprobar cómo referenciar el bedtime recordado sin convertirlo en horario autorizado. |
| 4 | `night_scroll_advice_question_no_action_link` | U | Conserva consejo sin enlace ni acción. La pregunta es pertinente, pero el texto es repetitivo y no demuestra una respuesta útil al consejo solicitado. Regex insuficiente para decidir. |
| 5 | `bare_time_window_after_sleep_context_crosses_midnight` | M | Esperaba 22:00–06:00 y ejecución desde `10 to 6` y un tema recordado. Rechazar la inferencia es correcto; estado vacío con `ask/apps` fuera de sus pendientes no es una transición canónica coherente. |
| 6 | `midnight_bedtime_boundary` | M | Esperaba inferir medianoche y una ventana de 30 minutos desde bedtime. No debe ejecutarse; la respuesta actual tampoco conserva el dato de bedtime ni pregunta su ambigüedad. |
| 7 | `explicit_night_window` | O | `Block Instagram from 10 to 7` esperaba 22:00–07:00 dentro del picker. Estado conserva Instagram, deja horas ambiguas y pide aclaración; evita AM/PM y payload inventados. |
| 8 | `sleep_goal_window_infers_pre_bed_boundary` | M | El assert inventaba 22:45–23:00 y siete días desde una meta de sueño. Suprimir acción es correcto; perder la meta explícita y pasar a una pregunta genérica de bloqueo no cumple comprensión. |
| 9 | `explicit_evening_window` | O | Conserva TikTok y 21:00–23:00; pide recurrencia faltante. Picker inmediato con horarios y score por bullets no eran requisitos seguros. |
| 10 | `remembered_app_broken_plan` | M | Una recaída recordada no autoriza horario. La nueva respuesta pierde contexto y su `ask/apps` no aparece en el estado canónico. |
| 11 | `focus_now` | M | No existe duración, selección explícita ni recurrencia/confirmación para iniciar. Pero `now` y el objetivo laboral desaparecen del estado y la decisión no corresponde a pendientes. |
| 12 | `study_window` | M | Examen mañana no autoriza simultáneamente horario y límite diario. La respuesta genérica ignora el objetivo y fecha, y no discrimina consejo de petición de bloqueo. |
| 13 | `urge_not_active` | M | No procede iniciar bloqueo indefinido y duro automáticamente. La sustitución pierde el apoyo solicitado y fabrica una propuesta discursiva que el estado no contiene. |
| 14 | `allow_only_essentials` | R | `Only let me use WhatsApp and Maps` tiene intención de permitir únicamente esas apps. Se transforma en “qué apps bloquear”, sin conservar lista permitida ni reconocer capacidad pendiente. La ejecución anterior requería confirmación, pero la intención sigue siendo válida. |
| 15 | `weekly_review` | R | `Review my week` se sustituye por pregunta para bloquear apps. Evitar `apply_ai_plan` automático no justifica omitir la revisión ni las métricas disponibles. |
| 16 | `adult_filter` | R | Solicita filtrar webs adultas y recibe wizard de apps/horarios. Debe reconocer filtro de contenido y sus permisos/confirmación o declarar su capacidad limitada. |
| 17 | `spanish_emergency` | M | El bloqueo duro automático era indebido. La respuesta observada está en inglés pese al español, y pierde Instagram y la necesidad de ayuda. |
| 18 | `contradiction_work_app` | R | TikTok queda como objetivo, pero la excepción de uso laboral no se representa. Preguntar una hora genérica no resuelve esa restricción ni impide un plan incompatible posterior. |
| 19 | `block_everything_except_essentials` | R | Se pierde la semántica de excepción/allow-only y la lista WhatsApp/Maps. La ausencia de acción es segura pero incompleta. |
| 20 | `unknown_app_duolingo_picker` | O | Duolingo se conserva exactamente en el estado; se pregunta inicio faltante y no se actúa. El nombre no tiene que repetirse en cada pregunta para conservarse. |
| 21 | `ambiguous_time_without_context` | O | El assert inventaba 07:00–08:00 desde `7 to 8`. Ahora las horas quedan pendientes y no se entrega picker ejecutable. |
| 22 | `explicit_morning_focus_window` | M | No hay autorización ni fecha nativa suficiente para ejecutar mañana. Sin embargo, el contexto explícito “tomorrow morning from 8 to 10” se pierde por completo en estado/seguimiento. |
| 23 | `held_plan_repeat` | M | Un resultado histórico favorable no confirma repetir un horario. Pero “Instagram after dinner” literal desaparece del estado y se vuelven a preguntar datos ya dados. |
| 24 | `open_report_diagnostic` | M | Una pregunta “why” no autoriza protección. La respuesta no explica ni conserva el momento señalado; vuelve al bloqueo genérico con estado de consejo vacío. |
| 25 | `reddit_named_app` | O | Reddit y `tonight`/una vez quedan conservados; falta inicio y duración. No mencionar bedtime en la pregunta no demuestra pérdida del dato. |
| 26 | `spanish_explicit_window` | O | Conserva Instagram, 22:30–23:30 y español; pregunta recurrencia. El picker temprano y el texto de rango en inglés eran expectativas obsoletas. |
| 27 | `study_spanish_youtube` | M | Estudiar sin YouTube esta tarde no autoriza dos acciones automáticas. Aun así, app y momento literales se pierden y se vuelve a preguntar qué app. |
| 28 | `work_distraction_focus` | M | Un problema de distracción no confirma bloqueo inmediato. La respuesta omite ayuda contextual y la fase de consejo, con decisión incompatible con el estado vacío. |
| 29 | `sleep_bedtime_1030` | M | El assert deducía PM y un bloqueo previo de 30 minutos. Evitarlo es correcto; el dato de bedtime necesita preservarse/clarificarse, no sustituirse por solicitud de apps. |
| 30 | `sleep_known_bedtime_followup` | M | `usually 12` no autoriza 23:30–00:00. Pero no hay una pregunta de aclaración sobre “12”; el siguiente paso público y el estado vuelven a divergir. |
| 31 | `relapse_after_break` | M | El assert pedía un nuevo bloqueo duro desde un hecho pasado. El core también interpreta erróneamente ese pasado como intención `block` y duración futura de 15 minutos: defecto duro real aunque todavía no actúe. |
| 32 | `adult_spanish` | R | “bloquear porno” se convierte en apps+horarios. Debe conservar la intención de filtro y ofrecer únicamente un paso compatible y confirmado. |
| 33 | `block_social_media_category_not_app` | O | Conserva categoría `social_apps` y `after lunch` sin inventar apps. Preguntar primero apps frente a final del almuerzo es una diferencia de orden válida. |
| 34 | `block_instagram_setup_overrides_tiktok_memory` | O | El estado contiene Instagram y no TikTok; no hay acción y se pide inicio. Falla únicamente por exigir nombre/App/choose en el texto. |
| 35 | `weak_hour_remembered_no_app` | M | Memoria de una hora problemática no autoriza repetir un bloqueo. Se pierde la referencia contextual y la decisión no se registra en pendientes. |
| 36 | `hard_mode_request` | M | Faltan apps, recurrencia y confirmación, por lo que no actuar es correcto. La petición explícita de modo duro tampoco se conserva; la construcción actual fija `hard_mode:false`, lo que sería una alteración posterior. |
| 37 | `existing_work_mode_start` | M | Un nombre en `available_modes` no prueba selección/permisos ni autoriza inicio implícito. Pero se pierde la referencia Work y los 45 minutos en vez de conservarlos como petición pendiente. |
| 38 | `existing_sleep_mode_schedule` | M | El assert activaba modo y horario ambiguo sin recurrencia/confirmación. La implementación también pierde el modo nombrado y los tiempos que deberían quedar pendientes de aclarar. |
| 39 | `block_instagram_after_dinner_context_question` | O | App y momento se conservan; pide el inicio real sin inventar duración. La pregunta podría mencionar cena con más naturalidad, pero el fallo exacto es de wording, no pérdida del slot. |
| 40 | `synthetic_sleep_target_midnight_creates_boundary` | M | Se inventaba 23:30–00:00 desde una meta. Ahora no ejecuta, pero tampoco conserva esa meta ni ofrece seguimiento contextual. |
| 41 | `spanish_after_lunch_context_question` | O | Categoría y después de comer se conservan, respuesta en español sin acción. El orden apps→horario difiere del assert sin demostrar error duro. |
| 42 | `spanish_work_conflict_no_action` | R | La restricción laboral no tiene representación semántica; solo se pregunta hora. Debe resolverse antes de confirmar una regla incompatible. |
| 43 | `spanish_overreach_no_absolute_block` | O | Se rechaza duración sin límite y se pide una duración finita, sin acción. `social` frente a `general` es taxonomía heredada; no se promete bloqueo permanente. |
| 44 | `emotional_low_state_can_offer_action` | M | Sentirse mal no autoriza bloqueo ni demuestra un problema digital. La respuesta continúa forzando una propuesta de bloqueo y omite reconocimiento/contexto. |
| 45 | `spanish_work_anchor_time_creates_window` | O | El assert inventaba inicio a las 18:10 y fin a las 19:10. Ahora conserva el inicio explícito 18:00 y pide duración/recurrencia faltantes. |
| 46 | `tonight_short_window_stays_pm` | M | Un picker temprano sigue siendo inseguro; además, no resolver “10 to 11 tonight” evidencia una limitación de comprensión del marcador temporal explícito. No se debe ocultar como mera confirmación faltante. |
| 47 | `proactive_social_spike_creates_short_window` | M | Señal de 42% no autoriza 13:10–14:00 durante tres días. El reemplazo omite por qué se interrumpe y produce una decisión sin estado correspondiente. |
| 48 | `proactive_repeated_breaks_starts_hard_block` | M | Tres recaídas no autorizan bloqueo duro indefinido. La respuesta pierde la señal y fuerza un wizard genérico. |
| 49 | `proactive_weak_window_near_creates_boundary` | M | Riesgo próximo no confirma 21:10–22:00 durante tres días. No se conserva ni comunica la señal como explicación contextual. |
| 50 | `proactive_low_recovery_creates_sleep_boundary` | M | Recuperación baja no autoriza 21:30–23:00. La respuesta omite señal, contexto y permiso para proponer protección. |
| 51 | `web_scroll_adds_small_app_conversion_note` | U | Estado de consejo conserva Instagram/noche y no ejecuta. `sleep` frente a `general` no prueba fallo semántico; utilidad del consejo y conveniencia de una nota comercial requieren evaluación de calidad. |
| 52 | `explicit_schedule_names_requested_app` | O | Conserva YouTube y 22:00–07:00; pide recurrencia. No corresponde anticipar selección ni ejecución; fallar por score/bullets no invalida esos hechos. |

## Bloqueos que esta adjudicación conserva

1. La frontera que retira acciones no debe fabricar `ask/apps` mientras el estado dice `idle` y no contiene pregunta pendiente, ni borrar el significado de consejo, revisión o señales.
2. Retrospectivas, restricciones de uso laboral, allow-only y filtro adulto necesitan intención explícita o una respuesta de capacidad limitada; no pueden convertirse silenciosamente en bloqueo ordinario.
3. Las peticiones de modo duro o modo guardado deben preservarse o declararse no ejecutables con el protocolo vigente; nunca cambiarse silenciosamente a valores por defecto.
4. La conservación de contexto declarativo —deseos, objetivos de sueño, momentos, apps y horas— necesita pruebas independientes, además de las órdenes que empiezan por “Block”.
5. Los cuatro casos U requieren juicio de calidad y los 35 casos M/R requieren cierre por evidencia nueva. Los ejemplos corregidos tras leer esta tabla pasan a ser regresiones conocidas; no siguen siendo holdout.

## Criterio de cierre

Mantener el resultado original y su mapeo. Para cada corrección posterior, añadir replay con los mismos inputs, snapshot de fuentes y expectativas semánticas escritas antes de ejecutarlo. No sumar estos resultados a una media que oculte los bloqueos. No declarar release por mover el evaluador anterior a “diagnóstico”: esa decisión solo elimina un indicador inadecuado, no resuelve las regresiones descritas aquí.

## Delta final — 2026-09-15, ejecución de las 18:13 UTC

Se compararon los IDs de `tmp/bm-semantic/release-gate.json` —inicio `2026-09-15T18:13:53.540Z`, fin `18:13:59.199Z`— con los 52 IDs conservados en `tmp/bm-semantic/legacy-adjudication-replay.json`. Esta adenda solo inspecciona los resultados y el código vigente; no modifica ni vuelve a ejecutar casos para hacerlos pasar.

| Medida del evaluador anterior sin modificar | Resultado |
|---|---:|
| Fallos originales | 52/114 |
| Fallos finales | 61/114 |
| Aprobados finales por ese evaluador | 53/114 |
| IDs fallidos que permanecen | 52 |
| IDs fallidos añadidos | 9 |
| IDs recuperados | 0 |

**La coincidencia de IDs no demuestra que los 52 fallos mantengan la misma causa.** Algunos errores semánticos se corrigieron y pueden seguir fallando antes por vocabulario, acción esperada o contrato anterior. Tampoco demuestra que los 35 defectos reales inicialmente identificados estén cerrados. La tabla histórica conserva su significado y no se sustituye por una exención global de los 61.

### Los nueve fallos añadidos

| ID | Primer fallo final | Interpretación y límite de la evidencia |
|---|---|---|
| `pause_rules` | `action_types` | Ya no sale la mutación legacy `pause_rules` por una petición de pausa semanal. Restricción explícita de capacidad hasta tener contrato canónico propio; no significa que la función de pausa esté completada. |
| `resume_rules` | `action_types` | Se retira `disable_pause` legacy. Reanudar reglas sigue siendo una intención válida, pero este camino conversacional no puede ejecutarla sin estado validado. |
| `mixed_language_night_scroll` | `text_matches:bedtime\|sleep target\|sleep` | El primer fallo es lexical y no demuestra por sí solo error duro. Conservación de objetivo de sueño, idioma mixto y utilidad siguen pendientes de revisión específica; no se declara aprobado. |
| `contradiction_work_app_instagram` | `ui_text_matches:Tell me when Instagram becomes non-work use` | El core identifica la limitación de distinguir uso laboral dentro de una app y evita ejecutarla. No cumplir esa frase exacta no prueba una regresión, pero la restricción laboral requiere revisión manual y continúa siendo una capacidad limitada. |
| `instagram_after_lunch_asks_real_lunch_time` | `ui_text_matches:What time do you usually finish eating` | El assert exige una formulación concreta de la pregunta. La conservación del momento y app debe verificarse con estado/slots; no se cambia la fixture ni se adjudica calidad por semejanza lexical. |
| `spanish_night_scroll` | `text_matches:noche\|dormir\|hora objetivo\|sueño\|scroll` | Sigue abierta la valoración de contexto de sueño y utilidad de la respuesta en español. Un fallo de palabras concretas no certifica ni invalida equivalencia semántica. |
| `work_app_conflict_youtube` | `ui_text_matches:Tell me when YouTube becomes non-work use` | Igual limitación real de uso laboral que Instagram. La respuesta de capacidad limitada no es el wizard anterior; no se promete una regla que diferencie usos dentro de YouTube. |
| `vacation_spanish` | `action_types` | La expectativa de `pause_rules` con 168 horas ya no puede ejecutarse desde fallback. Además, “estoy de vacaciones” no aporta una duración semanal explícita. La pausa conversacional permanece restringida. |
| `resume_spanish` | `action_types` | La mutación `disable_pause` queda deshabilitada en el camino legacy también en español. No se presenta como capacidad canónica implementada. |

En conjunto: **4 nuevos fallos por retirada explícita de mutaciones legacy** y **5 primeros fallos de texto/contexto**, de los cuales 2 están vinculados a la limitación de uso laboral. No se asigna aprobación semántica automática a ninguno por esta agrupación.

### Frontera de ejecución final

`enforceSemanticBoundary` en `netlify/functions/blanked-agent.js` ya retira todas estas mutaciones del camino legacy: `start_protection`, `activate_mode`, `apply_schedule`, `set_daily_limit`, `apply_ai_plan`, `enable_allow_only`, `enable_adult_filter`, `pause_rules`, `disable_pause` y `switch_mode`. Los tipos de protección implementados por el reducer solo pueden salir desde estado completo y confirmado. Una interfaz de selección o permisos sin payload ejecutable no equivale a una acción aplicada.

Esto introduce una restricción visible de producto: filtro adulto, listas de excepciones, pausa/reanudación y cambio de modo legacy no quedan disponibles para ejecución conversacional solo porque existieran sus acciones antiguas. Deben revisarse manualmente o disponer de contrato canónico propio. El rechazo de ejecución prematura es una mejora de seguridad, no una prueba de paridad completa de capacidades.

El JSON final informa `automated_checks_passed: true`, pero mantiene `production_release_verified: false` y `active_model_checked: false`. El primer indicador corresponde a sus checks automatizados, no transforma el diagnóstico legacy de 61 fallos en verde ni certifica producción. Permanecen explícitos el modelado incompleto de objetivos de sueño/bedtime, la utilidad de consejo y proactividad, y las capacidades restringidas. La mejora global solo puede juzgarse con la evidencia semántica y humana independiente correspondiente.
