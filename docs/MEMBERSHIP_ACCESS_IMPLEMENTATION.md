# Blank Membership Access

## Objetivo

Implementar acceso por codigo para iOS sin romper la app existente:

- Shopify confirma compra.
- Backend genera codigo unico.
- Cliente recibe el codigo por email y, mas adelante, en la pantalla post-compra.
- iOS canjea el codigo y queda vinculado al `app_install_id`.
- Si el estado deja de ser `trial_active` o `active`, la app vuelve a la pantalla de activacion.

## Planes

| Plan | Estado inicial | Dispositivos | Periodo |
| --- | --- | ---: | --- |
| `trial` | `trial_active` | 1 | 30 dias gratis |
| `monthly` | `active` | 1 | 30 dias |
| `annual` | `active` | 1 | 365 dias |
| `family` | `active` | 5 | 365 dias |

El plan de prueba es el unico con trial gratis. Mensual, anual y familiar pagan desde el dia 1.

## Endpoints

Base URL para iOS:

```txt
https://<site>.netlify.app/.netlify/functions
```

Configurar esa URL en iOS como `BlankMembershipAPIBaseURL`. En Xcode se ha dejado preparada la clave de `Info.plist` mediante el build setting `BLANK_MEMBERSHIP_API_BASE_URL`.

### App iOS

```txt
POST /redeem-code
POST /membership-status
```

Body:

```json
{
  "code": "BLANK-7K4Q-92FD",
  "app_install_id": "UUID",
  "platform": "ios"
}
```

Respuesta:

```json
{
  "status": "active",
  "plan": "annual",
  "max_devices": 1,
  "trial_ends_at": null,
  "current_period_ends_at": "2027-08-03T10:00:00.000Z"
}
```

### Shopify

```txt
POST /shopify-orders-paid
```

Webhook recomendado inicial: pedido pagado. El endpoint:

- verifica firma HMAC de Shopify o `SHOPIFY_WEBHOOK_TOKEN` si no hay app secret disponible;
- detecta plan por selling plan, texto/nombre de plan o variant ID/SKU;
- ignora el pedido si no detecta un plan de membresia;
- genera codigo unico;
- crea la membresia;
- envia email si Resend esta configurado.

### Admin / automatizaciones

```txt
POST /membership-admin-create-code
POST /membership-admin-update
```

Protegido con:

```txt
Authorization: Bearer <MEMBERSHIP_ADMIN_SECRET>
```

Crear codigo manual:

```json
{
  "plan": "annual",
  "email": "cliente@example.com",
  "send_email": true
}
```

Respuesta:

```json
{
  "code": "BLANK-7K4Q-92FD",
  "entitlement": {
    "status": "active",
    "plan": "annual",
    "max_devices": 1
  }
}
```

Sirve para actualizar estado desde una automatizacion, Shopify Flow, Zapier o un webhook especifico de la app de suscripciones:

```json
{
  "code": "BLANK-7K4Q-92FD",
  "status": "cancelled"
}
```

Tambien acepta `order_id`, `trial_ends_at`, `current_period_ends_at` y `shopify_subscription_id`.

## Variables De Entorno

```txt
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
SHOPIFY_WEBHOOK_SECRET
SHOPIFY_WEBHOOK_TOKEN
MEMBERSHIP_ADMIN_SECRET
PUBLIC_ACTIVATION_LOOKUP_ENABLED=false

SHOPIFY_TRIAL_VARIANT_IDS
SHOPIFY_MONTHLY_VARIANT_IDS
SHOPIFY_ANNUAL_VARIANT_IDS
SHOPIFY_FAMILY_VARIANT_IDS
SHOPIFY_TRIAL_SELLING_PLAN_IDS
SHOPIFY_MONTHLY_SELLING_PLAN_IDS
SHOPIFY_ANNUAL_SELLING_PLAN_IDS
SHOPIFY_FAMILY_SELLING_PLAN_IDS
DEFAULT_MEMBERSHIP_PLAN=annual

RESEND_API_KEY
RESEND_FROM_EMAIL
RESEND_REPLY_TO_EMAIL
```

Los `SHOPIFY_*_VARIANT_IDS` aceptan lista separada por comas. Pueden ser IDs numericos de variant, GIDs de Shopify o SKU.
Los `SHOPIFY_*_SELLING_PLAN_IDS` aceptan lista separada por comas. El webhook prioriza selling plan, despues texto/nombre del plan y por ultimo variant. Si no detecta ningun plan, responde como ignorado y no crea codigo.

IDs actuales de Appstle Memberships en Shopify:

```txt
trial: gid://shopify/SellingPlan/691965231447
monthly: gid://shopify/SellingPlan/691965264215
annual: gid://shopify/SellingPlan/691965690199
family: gid://shopify/SellingPlan/691965722967
```

## Supabase Schema

Ejecutar en Supabase SQL editor:

```sql
create extension if not exists pgcrypto;

create table if not exists membership_codes (
  id uuid primary key default gen_random_uuid(),
  activation_code text not null unique,
  code_hash text not null unique,
  status text not null check (status in ('trial_active', 'active', 'past_due', 'cancelled', 'expired')),
  plan text not null check (plan in ('trial', 'monthly', 'annual', 'family')),
  max_devices integer not null default 1,
  shopify_order_id text unique,
  shopify_order_name text,
  shopify_confirmation_number text,
  shopify_customer_id text,
  shopify_subscription_id text,
  customer_email text,
  trial_ends_at timestamptz,
  current_period_ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists membership_devices (
  id uuid primary key default gen_random_uuid(),
  membership_id uuid not null references membership_codes(id) on delete cascade,
  app_install_id text not null,
  platform text not null default 'ios',
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (membership_id, app_install_id)
);

create index if not exists membership_codes_code_hash_idx on membership_codes(code_hash);
create index if not exists membership_codes_order_idx on membership_codes(shopify_order_id);
create index if not exists membership_devices_membership_idx on membership_devices(membership_id);
```

## Siguiente Paso Shopify Thank You

La pantalla post-compra debe ser una Checkout UI Extension que:

1. Lee el order id disponible en Thank You / Order Status.
2. Llama a `POST /shopify-order-activation-code` con `order_id`.
3. Envia tambien `order_name` o `confirmation_number` para verificar que esta viendo ese pedido.
4. Muestra el codigo si existe.
5. Si recibe `preparing_code`, reintenta unos segundos.

Ese endpoint admite dos modos:

- Admin: `Authorization: Bearer <MEMBERSHIP_ADMIN_SECRET>`.
- Publico para extension: `PUBLIC_ACTIVATION_LOOKUP_ENABLED=true` y body con `order_id` + `order_name` o `confirmation_number`.

## Limitacion Actual

El backend queda listo para desplegar, pero no puede funcionar en produccion hasta configurar:

- Supabase y sus tablas.
- Variables de entorno en Netlify.
- Webhook de Shopify.
- IDs de variantes/productos.
- Resend o proveedor de email.
