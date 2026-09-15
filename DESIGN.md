# Blankmind NewLook visual system

This branch is the visual replacement prototype for the native iOS app. It translates the supplied NewLook1/NewLook2 references into a text-led interface without the reference number or asterisk.

## Direction

Blankmind behaves like an editorial list, not a dashboard. Content is sparse, aligned to the leading edge, and ordered by importance. The light world uses a warm off-white field; the protected/active world uses a quiet near-black field. Hierarchy comes from scale, weight, opacity, and line breaks. Containers, gradients, glass, decorative icons, and card stacks are not part of this world.

## Tokens

- `light.background`: `#F3F3EF`
- `light.ink`: `#1D1E1D`
- `light.secondary`: `#636560`
- `light.faded`: `#BABBB6`
- `dark.background`: `#1B1B1D`
- `dark.ink`: `#FFFFFF`
- `dark.secondary`: `#4A4A4E`
- `interaction`: restrained system blue for navigation and links
- `display`: Inter/SF-compatible bold text, usually 32–42pt for primary actions
- `support`: 12–20pt medium text with tight leading
- `touch`: minimum 44pt interactive frame

## Surface grammar

Home and section screens are full-bleed fields with a single editorial column. Rows are transparent and separated by rhythm rather than boxes. Primary actions are text-first. Native toggles, pickers, alerts, permission sheets, and forms remain native controls so behavior and accessibility are preserved.

## State grammar

Idle uses warm light. Active protection uses near-black and white text. Secondary or unavailable actions use subdued gray. No state depends on color alone; wording, opacity, and native control state carry meaning.

## Scope

This document covers the NewLook prototype branch only. Product behavior, Screen Time/FamilyControls, assistant messaging, membership, permissions, setup, and recovery workflows remain the source of truth from the existing app.
