# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

Primary users are people who want to reduce compulsive phone use and protect focused time. They use Blankmind on an iPhone when they need a fast, low-friction way to start a blank/protected period, understand their patterns, plan limits, or recover from an interruption.

## Product Purpose

Blankmind helps people create intentional distance from distracting apps through device-level protection, simple planning, timing, emergency access, and reflection. Success means a user can understand the available action and start the right flow within seconds, without navigating a dense dashboard.

## Positioning

Blankmind combines a simple conversational support layer with native iOS Screen Time and device controls, so the product can turn an intention to focus into an actual protected state rather than only offering advice or tracking.

## Operating Context

The app is evaluated and used on iPhone through the native iOS app and simulator. Core journeys include first-time setup and permissions, starting and ending a blank/protected period, viewing stats, planning protection, using a timer, emergency access, settings, assistant connection, and recovery/relink flows.

## Capabilities and Constraints

- Preserve all existing workflows, callbacks, permission requests, Screen Time/FamilyControls integration, authentication, membership gating, and assistant/message flows.
- This branch is a visual replacement prototype; it must not alter product behavior merely to achieve the new appearance.
- The home should expose the main actions as a short text list: blank, stats, plan, timer, settings. Emergency belongs inside settings rather than as a primary home item.
- Remove the legacy card/dashboard identity, the decorative home number, and the decorative asterisk from the new visual world.
- Respect native iOS safe areas, Dynamic Type where practical, VoiceOver labels, and minimum touch targets.

## Brand Commitments

The product name is Blankmind. The supplied NewLook1.jpg and NewLook2.jpg references are binding visual references for this prototype, excluding their number 1 and asterisk. The target identity is radically simplified, text-led, sparse, editorial, premium, and low-noise. The visual system should support light off-white and dark near-black surfaces with strong black/white type, subdued gray hierarchy, and restrained interactive color.

## Evidence on Hand

- Visual references: `C:/Users/Guillem/Desktop/NewLook1.jpg` and `C:/Users/Guillem/Desktop/NewLook2.jpg`.
- Existing implementation and product behavior in `ios/Blank/Blank`.
- Product operating context in `Blank Brain/01_ESTADO.md`, `02_DECISIONES.md`, `03_TAREAS.md`, `04_APRENDIZAJES.md`, and `Blank Brain/PROCESOS/desarrollo.md`.
- No new testimonials, benchmarks, or product claims should be invented for this visual prototype.

## Product Principles

- Make the next useful action obvious.
- Remove interface chrome before adding explanation.
- Preserve the user’s momentum through protection and recovery flows.
- Let content hierarchy communicate state without decorative containers.
- Keep the product behaviorally trustworthy while the visual identity changes.

## Accessibility & Inclusion

Keep native iOS interaction affordances, readable contrast in both light and dark surfaces, scalable text, VoiceOver-accessible controls, and touch targets of at least 44 points. Do not rely on color alone to communicate state.
