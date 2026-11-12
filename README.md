# NaN Usage — widget Connect IQ para Forerunner 955 / 955 Solar

Muestra el consumo de **créditos** de la cuenta NaN (`nan.builders`) directamente en el
reloj: % de créditos consumidos del periodo en un anillo de progreso, dato héroe, días
hasta el reset del periodo, los 3 modelos que más créditos consumen en los últimos 30
días con barra, y una **glance** con el % consumido, los créditos que quedan y la edad
del último dato. Con la piel de marca **nan.builders**.

**Arquitectura:** la app NO habla Bluetooth con una app propia del móvil. Hace
`Communications.makeWebRequest()` → la petición viaja por BLE a **Garmin Connect Mobile**
en el teléfono emparejado, que es quien hace el HTTPS real y devuelve la respuesta al
reloj. **Sin teléfono emparejado no hay red** (errores `-300` / `-2` / `-104`). La
respuesta (~2,7 KB JSON con `credits` (`allowance`, `used`, `remaining`, `period_end`,
`frozen`), `totals` (`credits`, `by_model[]` con `model`/`credits` de los últimos 30
días) y `data[]` de muestra) se cachea en `Application.Storage`, así que la glance y las
aperturas sin cobertura muestran la última instantánea. **Política de refresco (batería
primero):**

- **Cero red en background**: sin Timer ni Temporal Events; el fetch ocurre SOLO al abrir
  la vista (o con SELECT). Al abrir se pinta la caché al instante y el refresco es
  asíncrono (el subtítulo añade `· actualizando...`; nunca una pantalla de espera).
- **Fetch al abrir SIEMPRE**, salvo anti-rebote de 30 s (`ANTI_BOUNCE_MS`) desde el último
  INTENTO (éxito o fallo): tras un fallo hay **backoff de 30 s** y no se reintenta
  automáticamente antes. El guard anti-doble-disparo de 20 s (`SYNC_TIMEOUT_MS`) se
  conserva como suelo mínimo entre intentos mientras una petición sigue en vuelo.
- **Edad del último fetch visible** (`hace 45s`, `hace 3 min`, `hace 2 h`,
  `hace 5 d`), en el subtítulo de la vista y también en la glance (que la lee de
  Storage, sin red). Se guarda en **epoch de pared** (`Time.now().value()`), así que
  sobrevive a reboots; si el reloj cambió de hora se muestra `hace ?` y se refresca.
  En el subtítulo, si la línea no cupiera en el ancho, la edad es lo último que se
  quita (después de la palabra "créditos"); las cifras nunca se quitan.
- **SELECT fuerza el refresco siempre** (bypass del anti-rebote).
- El aviso de fallo (`sin conexion · hace X`, ámbar) **persiste entre aperturas**:
  se guarda el resultado del último intento (`nan_last_err`) y un éxito lo borra.

```
GET https://api.nan.builders/v1/usage?limit=1
Authorization: Bearer <NAN_API_KEY>
```

## Datos: la cuenta va por CRÉDITOS

- **Fuente:** `GET https://api.nan.builders/v1/usage?limit=1` con la MISMA key `sk-`
  (cabecera `Authorization: Bearer`, sin sesión). El endpoint anterior
  (`cloud-api.nan.builders/api/usage/quota`) daba **topes de tokens por modelo** que no
  representan el consumo real: esa agregación mostraba un 13 % cuando el consumo real era
  un 55 %.
- **Qué significa el % (héroe, arco y semáforo):** `credits.used / credits.allowance` del
  **periodo de facturación** (`period_start` → `period_end`; p. ej. 3 884,6 de 7 000 →
  **55 %**).
- **Desglose por modelo:** `totals.by_model` ordenado por créditos (top 3 en pantalla).
  Son **créditos de los últimos 30 días** (ventana `start_date`..`end_date` del reporte),
  NO del periodo de facturación: la barra y la cuota de cada fila se calculan sobre
  `totals.credits` (p. ej. glm5.3 2 052,7 / 3 884,6 ≈ 53 %), **no sobre el allowance**
  (7 000). Por eso las filas no pueden parecer que suman el héroe.
- **Subtítulo:** `3.9K de 7.0K créditos · hace 12s`, con formato compacto (< 1000 →
  entero; ≥ 1000 → una decimal y `K`). Si no cabe en el ancho, se quita primero la
  palabra "créditos" y al final la edad; las cifras nunca.
- **Badge:** días hasta `period_end` (`RESET EN N D`). Si la respuesta trae
  `frozen: true`, el badge se sustituye por un aviso discreto ámbar sin caja
  (`CUENTA CONGELADA`).
- **Caché** (`Application.Storage`): `nan_credits` (instantánea serializada:
  allowance/used/remaining/frozen/día de reset + modelos con sus créditos, pre-ordenados)
  y `nan_fetch_epoch` (edad del último fetch, epoch de pared; la glance la lee con ese
  literal). Las claves antiguas `nan_models`/`nan_period_day` quedan huérfanas sin
  migración (cambió el formato de los datos).

## Piel de marca nan.builders

### Assets oficiales (en `resources/drawables/`)

| fichero | tamaño | origen | uso |
| --- | --- | --- | --- |
| `launcher_icon.png` | **40×40** | isotipo oficial `https://nan.builders/brand/nan-isotipo-color.png` (1024×1024) cuantizado a la paleta CIQ (fondo negro, hexágono GREEN→PURPLE con el ∞ del degradado) | icono de lanzador exigido por `compiler.json` de fr955 |
| `isotipo_mini.png` | 16×16 | mismo isotipo; anillo bicolor (3 aristas `COLOR_GREEN` + 3 `COLOR_PURPLE`) con **∞ blanco** | hueco inferior del arco en la vista principal; cabecera de la glance |
| `wordmark.png` | 96×15 | wordmark oficial `https://nan.builders/brand/nan-wordmark-white.svg` (220×33, `fill:none` → rellenado de blanco al rasterizar) | cabecera de la vista principal y de la glance |

Los tres se declaran en `resources/drawables/drawables.xml` (`LauncherIcon`, `Wordmark`,
`IsotipoMini`) y se cargan con `WatchUi.loadResource(Rez.Drawables.X)` para pintarlos con
`dc.drawBitmap(x, y, bmp)`. Si un bitmap no cargara en runtime, la vista cae a un fallback
de primitivas/fuentes sin romper nada (y siempre compila).

### Tabla hex de marca → constante CIQ

El fr955 tiene pantalla ARGB2222 de 8 bpp: **solo 64 colores reales**. `setColor()` acepta
`0xRRGGBB` pero el hardware lo cuantiza al color más cercano de su paleta, así que se usan
siempre constantes `COLOR_*` (exactas en el dispositivo). Nota importante: el violeta claro
de marca `#9B6BF0` **cuantizado solo daría gris**, por eso el violeta se aplica como
constante `COLOR_PURPLE`.

| hex de marca | uso | constante CIQ |
| --- | --- | --- |
| `#0B0B0C` (fondo) | fondo de la vista | `COLOR_BLACK` |
| `#FFFFFF` (texto) | héroe, % de las filas, wordmark | `COLOR_WHITE` |
| `#C9C9CC` / `#9A9A9E` (cuerpo/muted) | subtítulo, nombres de fila, etiquetas | `COLOR_LT_GRAY` (colapsan: jerarquía por TAMAÑO, no por tono) |
| blanco al 16 % (hairline) | líneas de 1 px, pista del arco y de las barras | `COLOR_DK_GRAY` |
| `#7D39EB` / `#9B6BF0` (violeta) | "%", badge, relleno de barras, isotipo | `COLOR_PURPLE` (`0xAA00FF`, el más cercano) |
| `#95DD4F` (lima) | verde del isotipo / estado OK | `COLOR_GREEN` (decisión semántica, no por RGB) |
| semáforo | arco por % de créditos consumidos y "QUEDAN" (glance) | `COLOR_GREEN` / `COLOR_YELLOW` / `COLOR_RED` |

El `#8B5CF6` que se usaba antes **no es color de marca y se ha eliminado**: el par
verde/violeta del isotipo oficial ES la marca.

### Reglas de color

- El **arco** mantiene el semáforo por el % de créditos consumidos del periodo
  (used/allowance; función, no decoración).
- Las **barras de las filas** son `COLOR_PURPLE` (marca) con la cifra SIEMPRE escrita en
  `COLOR_WHITE` (el número es la información; el color, el atajo). Nada de arcoíris.
- La **glance** conserva el color de severidad (ámbar/rojo/verde) en el valor de
  "QUEDAN" para no perder la señal crítica.
- Máximo 1-2 hairlines `COLOR_DK_GRAY` de 1 px por vista. Rectángulos con esquinas
  RECTAS (la marca tiene radio 0; prohibido `fillRoundedRectangle`).

### Tipografía

- Héroe: `Graphics.getVectorFont({:face => "Roboto-Black", :size => 62})`
  (fallback `FONT_NUMBER_MEDIUM`); "%" en Roboto-Black 26 (fallback `FONT_MEDIUM`)
  en un **segundo** `drawText` violeta (nunca dos colores en una misma llamada).
- Fallback vectorial del wordmark (solo si el bitmap no carga): "naN" en
  `Roboto-Black` 16 + ".builders" en `RobotoCondensed-RegularItalic` 16 — ambas caras
  verificadas en el Device Reference de fr955 (nada de `:Roboto_Black` con guion bajo).
- Glance: solo fuentes de sistema (`FONT_GLANCE*` / `FONT_XTINY`), sin vector fonts
  (presupuesto de 64 KB del proceso glance).
- `Lang.String` no tiene `toUpperCase()` en el SDK 9.3.0: hay un helper ASCII propio.

### Diseño "Órbita" (260×260, centro 130,130)

- **Arco**: radio 112, grosor 10, 240° de barrido con hueco de 120° abajo
  (`degreeEnd = 210 − 240 · fracciónUsada`), pista `COLOR_DK_GRAY`, progreso con
  semáforo por % de créditos (verde < 50 %, ámbar 50–80 %, rojo > 80 %).
- **Cabecera de marca**: wordmark 96×15 centrado en y≈48 + hairline 1 px (patrón
  `.sechead` de la web). Sin texto "NaN Cloud".
- **Héroe** con la base en y=133, blanco; "%" violeta al lado; **subtítulo** (top y=134)
  `3.9K de 7.0K créditos · hace 12s` en LT_GRAY, con la edad visible (segundos bajo
  1 min) y el sufijo `· actualizando...` durante el fetch; el aviso de error
  (`sin conexion · hace X`, ámbar) persiste entre aperturas.
- **Badge** `.btn-primary`: violeta, texto blanco MAYÚSCULAS `RESET EN N D` (días hasta
  `period_end`; negativos clampeados a 0, `null` → `SIN PERIODO`, ancho medido y
  abreviado por pasos). Con `frozen: true` → aviso ámbar `CUENTA CONGELADA` sin caja.
- **Filas** (bases de texto 192/209/226, top 176/193/210): top 3 por créditos de la
  ventana de 30 días; nombre x=64 LT_GRAY MAYÚSCULAS, créditos x=196 WHITE (`2.1K`),
  barra (y=197/214/231, x=64, ancho 132, alto 3) pista DK_GRAY + relleno PURPLE con la
  cuota del modelo sobre `totals.credits`.
- **Isotipo mini** (16×16) en el hueco del arco (x 122..138, y 224..240), sin solape.
- **Estado vacío**: cabecera de marca + mensaje centrado (`TEXT_JUSTIFY_VCENTER`).

## Estructura

- `manifest.xml` — widget para `fr955`, permiso `Communications`, propiedad `api_key`.
- `source/NaNUsageApp.mc` — entry point + `getGlanceView()`.
- `source/QuotaStore.mc` — fetch de `/v1/usage?limit=1`, parseo de créditos, caché,
  cálculo de días al reset.
- `source/NaNUsageView.mc` — pantalla principal + delegate.
- `source/NaNUsageGlanceView.mc` — vista de glance (solo caché y edad desde Storage,
  sin red).
- `resources/drawables/drawables.xml` — `launcher_icon.png` (40×40), `wordmark.png`
  (96×15) e `isotipo_mini.png` (16×16).
- `resources/settings/settings.xml` — declaración de la propiedad `api_key`.
- `resources/properties/properties.xml` — valor por defecto de `api_key` (vacío en el
  build canónico; ver "La API key" en la instalación).
- `devkey.der` / `devkey.pem` — clave RSA **4096** del desarrollador (PKCS#8 DER / PEM),
  con copias de seguridad `devkey4096.der` / `devkey4096.pem`. No versionar.
- `bin/NaNUsage.prg` — **build canónico** (sin API key), para la tienda.
- `bin/NaNUsage.personal.prg` — build personal con la key horneada (lo genera el
  lead con `scripts/bake-personal.sh`; no compartir). No se sube al repositorio.

## Compilar

```bash
# en este repo (standalone)
SDK=${CONNECTIQ_SDK:-$HOME/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.3.0-2026-10-20-95888f262}
$SDK/bin/monkeyc -f monkey.jungle -d fr955 -w -l 2 -O2 -y devkey.der -o bin/NaNUsage.prg

# o, dentro del monorepo de desarrollo
scripts/build.sh apps/nan-usage fr955             # → apps/nan-usage/bin/NaNUsage.prg
```

`devkey.der` **no está en el repositorio** (material de clave, ignorado por `.gitignore`).
Si clonas esto en otra máquina, genera la tuya antes de compilar:

```bash
openssl genrsa -out devkey.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in devkey.pem -out devkey.der -nocrypt
```

SDK 9.3.0, definición `fr955` del SDK Manager oficial. `devkey.der` es la clave privada
RSA **4096** (PKCS#8 DER) que firma el binario y el paquete de tienda.

> **Conserva esta clave con copia de seguridad** (`devkey4096.der` / `devkey4096.pem`,
> fuera de cualquier repositorio). La clave define la **autoría** de la app: los futuros
> updates en la Connect IQ Store solo se aceptan firmados con la MISMA clave. Si se
> pierde, la app no se puede actualizar y hay que publicarla como app nueva.

La compilación termina con `BUILD SUCCESSFUL` y 0 errores (`ERROR:`); los `WARNING` de
tipado de Monkey C (`-l 2`) son esperables y no afectan al binario.

## Instalar en el Forerunner 955 / 955 Solar (sideload)

La app móvil **Connect IQ NO instala archivos `.prg`** (desde 2025 solo instala desde la
tienda). El sideload es **por USB/MTP**, copiando el binario al almacenamiento del reloj.
La API key NO se puede editar desde ninguna app de Garmin en una app sideloaded (no hay
editor de ajustes fuera de la tienda/Beta) — véase "La API key" más abajo.

1. Cierra **Garmin Express** en el ordenador (bloquea el MTP del reloj).
2. Conecta el reloj por USB. En Linux móntalo con `jmtpfs` o `gvfs`; en macOS usa
   **OpenMTP**.
3. Copia el `.prg` a la **raíz de `GARMIN/APPS/`** (mayúsculas) con el nombre exacto
   `NaNUsage.prg` (evita múltiples puntos en el nombre). Usa el build adecuado:
   - `bin/NaNUsage.personal.prg` — **para instalar y usar ya** (key horneada), renómbralo
     a `NaNUsage.prg` al copiarlo.
   - `bin/NaNUsage.prg` — build limpio; requiere configurar la key (ver abajo) y está
     pensado para la tienda.
4. Desconecta el reloj con seguridad. Mostrará **"Verificando Connect IQ"** y el
   `.prg` **desaparece de `GARMIN/APPS/`**: eso es la instalación correcta. Suele no
   requerir reinicio.
5. La app aparece en la **lista de Apps** (botón superior derecho) y en el **glance
   loop** (deslizar desde la esfera).
6. Si algo falla, el log del reloj está en `GARMIN/APPS/LOGS/CIQ_LOG.YML`.

Requisito cumplido: los relojes actuales rechazan sideloads compilados con SDK < 7.4.3;
este proyecto usa **9.3.0** y clave 4096 → OK.

### La API key

En una app sideloaded **no existe editor de ajustes** (ni en Connect IQ móvil, ni en
Garmin Connect, ni en Express: eso es solo para apps de tienda o Beta). Tres formas
reales de poner la `api_key`, por orden de simplicidad:

1. **Hornearla como valor por defecto**: escribir
   `<property id="api_key" type="string">sk-...</property>` en
   `resources/properties/properties.xml` y recompilar. Cero fricción y funciona sin
   móvil.
   **ADVERTENCIA: ese `.prg` contiene la key en claro. NO compartir, NO subir a la
   tienda, NO versionar.** El flujo acordado: el lead genera un build personal
   (`bin/NaNUsage.personal.prg`) con la key horneada para instalar y usar ya, mientras
   que el build canónico `bin/NaNUsage.prg` queda **SIN key** para la tienda.
2. **Archivo `.SET`** en `GARMIN/APPS/SETTINGS/NaNUsage.SET`: formato binario sin
   documentar y frágil; históricamente se generaba con el simulador, que en este host
   NO arranca (segfault por FreeType/ABI). Última opción.
3. **Beta App**: mismo binario bajo un App ID alternativo, visible solo en tu cuenta,
   con settings editables en Garmin Connect y sin review. Nota: instalar betas está
   reportado como roto en 2026.

Recuerda: `makeWebRequest` pasa SIEMPRE por el proxy de Garmin Connect del teléfono
emparejado — con o sin key horneada, para sincronizar hace falta el móvil con Garmin
Connect.

## Compatibilidad

- El `.prg` se compila **por deviceId**: `monkeyc -d fr955`. `fr955` es UN solo deviceId
  (partNumber `006-B4024-00`, API level 5.2.0, pantalla 260×260 redonda, 64 colores) que
  cubre **Forerunner 955 Y 955 Solar**; **no existe un `fr955solar` separado**.
- Cualquier otro reloj requiere **recompilar** con su `-d` correspondiente y añadir ese
  producto a `<iq:products>` del manifest; el `.iq` de la tienda empaqueta un PRG por
  producto (`monkeyc -e`).
- Del catálogo de ~180 deviceIds, **59 cumplen** todos los requisitos de esta app
  (widget + glance + VectorFont + API ≥ 5.0).
- Familias donde SÍ podría recompilarse (misma arquitectura): Forerunner 965/265/570/970,
  fēnix 7/8/9, epix 2, Venu 3, vívoactive 6, MARQ Gen2/3, Descent Mk3, Approach S70,
  Enduro 3.
- Familias FUERA por API < 5.0 o sin VectorFont/glance: Forerunner 245/945/745/55,
  fēnix 5/6, Venu 2, Instinct 2, Edge 1040.
- **Advertencia de layout**: la vista usa coordenadas fijas 260×260. En pantallas de
  240/280/416/454 px o rectangulares habría que parametrizar el layout con
  `s = min(w, h) / 260` antes de añadir esos productos.

## Publicar en la Connect IQ Store

Prerrequisitos ANTES de subir (los tres, en este orden):

1. **Clave RSA 4096 ya generada y con copia de seguridad** (hecho: `devkey.der` +
   `devkey4096.der`/`devkey4096.pem`). Perderla = perder la autoría y las actualizaciones.
2. **Política de privacidad publicada** (URL obligatoria en la ficha): debe decir que la
   API key del usuario viaja a `api.nan.builders`, que la app no la comparte con
   nadie más y que el responsable del dato es el usuario, no Garmin (GDPR).
3. **Plan de prueba para el revisor**: una API key demo de solo lectura/temporal de
   nan.builders + 3 pasos cortos en las "notas para el revisor", y **permiso escrito de
   nan.builders para usar la marca "NaN" y su logo** (es propiedad intelectual de un
   tercero).

Pasos:

1. Cuenta de desarrollador y aceptación del **Connect IQ Agreement**:
   <https://developer.garmin.com/downloads/connect-iq/sdks/agreement.html>
2. Generar el paquete de tienda (el Store pide `.iq`, no `.prg`):
   ```bash
   scripts/export-iq.sh apps/nan-usage /tmp/opencode/NaNUsage.iq
   ```
   Con un solo producto en el manifest, el `.iq` es de 1 dispositivo (fr955): es lo
   correcto. Ya verificado: `BUILD SUCCESSFUL`, "1 OUT OF 1 DEVICES BUILT", archivo
   7-zip.
3. Subirlo en <https://apps.garmin.com/en-US/developer/upload> (dashboard:
   <https://apps-developer.garmin.com>).
4. Guías oficiales: <https://developer.garmin.com/connect-iq/submit-an-app> y
   <https://developer.garmin.com/connect-iq/core-topics/publishing-to-the-store/>
5. Revisión de Garmin: ~72 h. Las **Beta Apps** se publican sin review pero solo son
   visibles en tu cuenta.

Checklist de la ficha: título ≤ 50 caracteres; descripción ≤ 4000; categoría; precio;
**URL de Privacy Policy (obligatoria)**; imágenes (icono de tienda 500×500, 1–5 screen
images, hero 1440×720, icono on-device 128×128); release notes; **notas para el
revisor**; email/URL de soporte.

Notas técnicas para la ficha: no hay whitelist de dominios en el manifest (solo el
permiso `Communications`), pero la petición debe ser **HTTPS con certificado público
válido** (lo es: `api.nan.builders`). Hay que **declarar la dependencia de un
servicio de pago ajeno** (NaN Cloud, con la API key del usuario). Publicar es gratis;
las apps de pago requieren 100 USD/año + 15 % de comisión de Garmin.

## Resolución de problemas

Instalación:

- `Signature check failed` → binario firmado con clave < 4096, SDK viejo (< 7.4.3) o
  `.prg` compilado para otro dispositivo. Regenera con `devkey.der` (4096) y `-d fr955`.
- "app not compatible" → el `.prg` está compilado para otro `-d`; el fr955 solo acepta
  binarios `-d fr955`.
- El `.prg` sigue en `GARMIN/APPS/` tras desconectar → no pasó la verificación; mira
  `GARMIN/APPS/LOGS/CIQ_LOG.YML`. Cierra Garmin Express y reintenta la copia MTP.

Red y datos:

- `Sin API key (ajustes)` → el build canónico no lleva key horneada: usa el build
  personal o una de las opciones de "La API key".
- `API key rechazada` (401) → key caducada/rotada, o copiada con espacios. Créala de
  nuevo en el dashboard (Ajustes → API keys, empieza por `sk-`).
- `Sin conexión` (−300) / `Sin móvil/BLE` (−2 / −104) → Garmin Connect no está
  emparejado, sin sesión o sin cobertura; el widget traduce estos códigos a texto humano.
- `Respuesta inesperada` → HTTP 200 pero el JSON ya no trae el bloque `credits`
  (cambió la API); se conserva la caché anterior y el aviso persiste en el subtítulo.
- `HTTP -402` (respuesta demasiado grande) → la API `usage` con `limit=1` hoy devuelve
  ~2,7 KB; si
  crece, interponer un proxy que recorte el JSON a los campos necesarios.
