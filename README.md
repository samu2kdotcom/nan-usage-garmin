# NaN Usage

Widget Garmin que muestra el consumo de **créditos de tu cuenta de NaN Cloud** directamente en el reloj: cuánto llevas gastado del periodo, cuándo se resetea y qué modelos se lo están comiendo. Sin abrir el móvil.

| Glance (fr955) | Principal (fr265) | Proyección · 7 D (fr265) | Actividad · 7 D (fr265) |
| --- | --- | --- | --- |
| ![Glance](img/v1.3.0/fr955-0-glance.png) | ![Principal](img/v1.3.0/fr265-1-principal.png) | ![Proyección 7 D](img/v1.3.0/fr265-4-proyeccion-7d.png) | ![Actividad](img/v1.3.0/fr265-5-actividad.png) |

- **% del periodo** con semáforo (verde/ámbar/rojo) y días hasta el reset (`RESET EN 14 D`)
- **Top 4 de modelos** por consumo de los últimos 30 días, con barra
- **5 pantallas** (DOWN/UP para recorrerlas, BACK para salir):
  1. Principal: % del periodo, reset y top de modelos (**START** refresca)
  2. Desglose · 30 D: todos los modelos — **START** alterna **créditos** (blanco, `cr`) y **tokens** (azul, `tok`)
  3. Proyección · 24 H y 4. Proyección · 7 D: ritmo, proyección a fin de periodo, veredicto, lo que queda y cuándo se agota a ese ritmo (START también alterna la unidad; en tokens, `~` = equivalencia con tu mezcla de modelos)
  5. Actividad · 7 D: créditos por día en barras, peticiones, tokens por petición, % de caché e histórico de tokens
- **Glance** siempre visible: créditos que quedan y edad del último dato
- **Caché en el reloj**: sin conexión muestra la última instantánea; red solo al abrir (si el dato tiene más de 5 min) o con START, y el uso diario solo al entrar en las pantallas 3-5 (batería primero)

## Instalar (sin Connect IQ Store)

1. Descarga el `.prg` de tu reloj desde la última [**release**](https://github.com/samu2kdotcom/nan-usage-garmin/releases)
2. Cierra Garmin Express, conecta el reloj por USB y copia el archivo a **`GARMIN/APPS/`** renombrado a `NaNUsage.prg` (Windows/MTP nativo; macOS con [OpenMTP](https://openmtp.ganeshrvel.com/))
3. **Desconecta el cable** (o expulsa el volumen con seguridad) → el reloj muestra "Verificando Connect IQ…" y el `.prg` desaparece de `GARMIN/APPS` (es normal: ya está instalado). Aparece en Apps y en el glance loop.
4. Abre la app y pulsa **SELECT** (primera vez): te pide tu API key con el teclado del reloj. Se guarda en el reloj; para cambiarla después, **MENU** (en fr955: mantén pulsado **UP**; ver abajo).

**Actualizar a una versión nueva**: descarga el `.prg` de tu reloj y repite los pasos 1–2 (se sustituye la app). Si al reinstalar el reloj borra los datos de la app, te volverá a pedir la key — la vuelves a introducir con SELECT.

| Archivo | Reloj |
| --- | --- |
| `NaNUsage-fr955.prg` | Forerunner 955 / 955 Solar |
| `NaNUsage-fr965.prg` | Forerunner 965 |
| `NaNUsage-fr970.prg` | Forerunner 970 |
| `NaNUsage-fr255.prg` | Forerunner 255 |
| `NaNUsage-fr255m.prg` | Forerunner 255 Music |
| `NaNUsage-fr265.prg` | Forerunner 265 |
| `NaNUsage-fenix7.prg` | fēnix 7 / 7 Sapphire |
| `NaNUsage-fenix7s.prg` | fēnix 7S / 7S Sapphire |
| `NaNUsage-fenix7x.prg` | fēnix 7X / 7X Sapphire (7 Pro: pedir build) |

> **Requisito**: teléfono emparejado con Garmin Connect — la red del reloj pasa por la app de Garmin del móvil (`makeWebRequest` vía BLE).

## Tu API key

La app lee `https://api.nan.builders/v1/usage` con tu API key (`sk-…`, se crea en el dashboard de NaN → Ajustes → API keys). Una app instalada por USB **no tiene el editor de ajustes de Garmin** — es una limitación de Garmin: los ajustes solo existen para apps publicadas en la Connect IQ Store. Por eso la key se introduce **en el propio reloj**:

- Abre la app y pulsa **SELECT** → se abre el teclado del reloj con `sk-` ya precargado → teclea el resto de tu key y confirma. Se guarda en el reloj y se usa al momento.
- Para cambiarla más adelante: pulsa **MENU** (en fr955 no hay tecla MENU: mantén pulsado **UP**, que el firmware mapea a esa acción).
- La key no sale del reloj: solo viaja a `api.nan.builders` en la cabecera `Authorization` de la petición HTTPS.

En modelos con pantalla táctil (fr965, fr265, fr970, fēnix 7) el teclado es en pantalla; en los de solo botones (fr955, fr255) se navega con los botones — un par de minutos, una sola vez.

Alternativa (opcional):

- **Compilártelo tú** en 2 min, solo en local: escribe tu key en `resources/properties/properties.xml` y compila (ver abajo). ⚠️ Ese `.prg` lleva la key en claro: es solo para tu reloj — no lo compartas ni lo subas a ningún sitio.

## Compilar desde fuente

```bash
# SDK Connect IQ (monkeyc): apunta SDK a tu instalación.
# Descarga: https://developer.garmin.com/connect-iq/sdk/
# La línea de abajo sirve si lo tienes en ~/.Garmin/ConnectIQ/Sdks (ajústala si no):
export SDK="$(ls -d ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-* 2>/dev/null | sort | tail -n 1)"

# Clave de desarrollador (RSA 4096, solo la primera vez; consérvala fuera del repo):
openssl genrsa -out devkey.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in devkey.pem -out devkey.der -nocrypt

# Compilar (fr955 o tu modelo: -d fr265, fr965, fenix7, ...):
$SDK/bin/monkeyc -f monkey.jungle -d fr955 -w -l 2 -O2 -y devkey.der -o bin/NaNUsage.prg
```

- Atajo: `scripts/build.sh [deviceId]` (detecta el SDK y firma con `./devkey.der`). Entorno completo en Linux con el reloj por USB, sideload y agente local: [`DESARROLLO.md`](DESARROLLO.md)
- La clave (`devkey.der`) no está en el repo y define la autoría de la app: **conserva copia de seguridad fuera del repo**
- Otros modelos: añade el `<iq:product>` al `manifest.xml`, compila con `-d <deviceId>` y publica el `.prg` en la release
- El layout se escala solo a cada pantalla (base 260×260; píxel-idéntico en fr955)

## Next steps

- [ ] Más modelos bajo petición (fr570, fenix 8/9, Venu 4, epix…) — mismo pipeline, solo hace falta el deviceId
- [ ] CI con GitHub Actions: compilar los 7 productos en cada tag y adjuntarlos a la release automáticamente
- [ ] Multi-idioma de los textos de la app (hoy solo inglés)
- [ ] Validación visual automática en CI: correr `scripts/ui-shot.sh` por modelo y comparar capturas antes de publicar
- [ ] Si algún día entra a la Connect IQ Store: `.iq` vía `monkeyc -e`, política de privacidad y permiso escrito de la marca NaN
