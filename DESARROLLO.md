# Desarrollo en local (Linux) con el reloj por USB

Guía para compilar NaN Usage en un portátil Linux, probarla en el reloj
conectado por USB y trabajar con un agente de código local (**opencode** u
**omp**). Está escrita para **Omarchy** (Arch + Hyprland); en otras distros
cambian los nombres de paquetes, no el flujo.

```
┌───────────────── portátil ──────────────────┐        USB (MTP)
│ opencode / omp  ──► scripts/build.sh        │ ─────────────────► reloj Garmin
│                     scripts/sideload.sh ────┼──► GARMIN/APPS/     GARMIN/APPS/LOGS/
│ SDK + Devices en ~/.Garmin/ConnectIQ        │ ◄──────────────── (println / crash)
│ simulador: distrobox ubuntu:22.04 (opcional)│
└─────────────────────────────────────────────┘
```

Orden: **1)** paquetes → **2)** SDK y dispositivos → **3)** repo y clave →
**4)** compilar → **5)** reloj por USB → **6)** simulador (opcional) →
**7)** agente local.

> **Si vas a viajar**, deja hechos los pasos 1–3 con buena conexión: el SDK y
> los dispositivos pesan ~2 GB y el SDK Manager necesita login de Garmin.

---

## 1. Paquetes

En Omarchy se instala con `omarchy pkg add` (repos oficiales) y `yay` (AUR).
Para actualizar el sistema usa `omarchy update`, no `pacman -Syu`.

```bash
omarchy pkg add jdk17-openjdk git python libmtp gvfs-mtp glib2 distrobox
```

| paquete | para qué |
| --- | --- |
| `jdk17-openjdk` | `monkeyc` es Java (17+) |
| `libmtp`, `gvfs-mtp`, `glib2` (`gio`) | ver y copiar ficheros al reloj por MTP |
| `distrobox` | contenedor Ubuntu 22.04 para el simulador (sección 6) |

`java -version` debe dar 17 o más (`archlinux-java status` si tienes varios).

## 2. SDK y dispositivos

**Opción A — SDK Manager** (instalación limpia):

```bash
yay -S connectiq-sdk-manager    # AUR: lee el PKGBUILD antes de instalar
connectiq-sdk-manager
```

Inicia sesión con tu cuenta Garmin, descarga el SDK (≥ 9.x) y en *Devices* al
menos tu reloj (`fr955`, `fr965`, `fr265`, …). El SDK Manager escribe
`~/.Garmin/ConnectIQ/current-sdk.cfg`, que `scripts/build.sh` lee solo.

**Opción B — copiar de otra máquina donde ya funciona** (mismo SDK = mismo `.prg`):

```bash
rsync -a --info=progress2 OTRA_MAQUINA:.Garmin/ConnectIQ/{Sdks,Devices,Fonts} ~/.Garmin/ConnectIQ/
```

(`Fonts` solo la usa el simulador.) Luego apunta al SDK:

```bash
cat >> ~/.bashrc <<'EOF'
export CONNECTIQ_SDK="$(ls -d ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-* | sort | tail -n1)"
export PATH="$CONNECTIQ_SDK/bin:$PATH"
EOF
source ~/.bashrc && monkeyc --version
```

## 3. Repo y clave de firma

```bash
git clone https://github.com/samu2kdotcom/nan-usage-garmin ~/code/nan-usage
cd ~/code/nan-usage
```

`scripts/build.sh` firma con `./devkey.der` (o la ruta en `DEVKEY`). Está en
`.gitignore` y **no se versiona nunca**.

- **Si publicas versiones de la app**: usa *la misma* clave que firmó las
  anteriores. Cópiala de tu máquina habitual por un canal privado
  (`scp`, USB cifrado), `chmod 600 devkey.der`, y comprueba
  `git check-ignore -v devkey.der`. Perderla = perder la autoría de la app;
  guarda la copia de seguridad fuera del portátil.
- **Si solo pruebas en tu reloj**: genera una propia (ver
  [README → Compilar desde fuente](README.md#compilar-desde-fuente)).

## 4. Compilar

```bash
scripts/build.sh            # fr955 → bin/NaNUsage.prg
scripts/build.sh fr265      # otro modelo (debe estar en manifest.xml y en ~/.Garmin/ConnectIQ/Devices)
```

## 5. Reloj por USB (MTP)

Los Garmin recientes no son un disco USB sino un dispositivo **MTP**. GVFS
(`gvfs-mtp`) lo monta bajo `/run/user/$UID/gvfs/mtp:host=…`.

### Conectar

1. Conecta el cable (debe ser de datos; el de carga de Garmin lo es) con el
   reloj desbloqueado.
2. Comprueba:

   ```bash
   mtp-detect | grep -iE 'garmin|model'   # el reloj aparece
   gio mount -li | grep -i mtp            # URI mtp://...
   ```

3. Si no está montado, `scripts/sideload.sh` lo monta solo; si falla, ábrelo
   una vez en el gestor de archivos (Nautilus).

### Instalar

```bash
scripts/sideload.sh bin/NaNUsage.prg              # copia a GARMIN/APPS/
scripts/sideload.sh --logs-on bin/NaNUsage.prg    # y activa el log de println
```

**Desconecta el cable**: el reloj muestra "Verificando Connect IQ…", el `.prg`
desaparece de `GARMIN/APPS` (normal) y la app queda instalada.

### Logs del reloj

- **`System.println`** va a `GARMIN/APPS/LOGS/NaNUsage.TXT` si ese fichero
  existe (`--logs-on` lo crea vacío; mismo nombre base que el `.prg` instalado).
- **Crashes** ("IQ!" en pantalla): `GARMIN/APPS/LOGS/CIQ_LOG.YML`
  (`CIQ_LOG.TXT` en firmware antiguo).
- Traerlos: `scripts/sideload.sh --pull-logs /tmp/ciq-logs`. La pila solo
  cuadra con el `.prg` del mismo build.

### Problemas típicos

| síntoma | arreglo |
| --- | --- |
| `mtp-detect` no ve el reloj | cable de solo carga u otro puerto; reconecta con el reloj desbloqueado |
| "device busy" / `LIBMTP_ERROR` | otro proceso tiene la sesión MTP (Nautilus, `jmtpfs`…): `gio mount -u` y reconecta |
| la app no aparece al desconectar | compilada para otro `deviceId`, o el firmware tiene API < `minApiLevel` (4.2.0) |
| "IQ!" al abrir | crash: mira `CIQ_LOG.YML` |

## 6. Simulador (opcional)

El simulador de Garmin enlaza contra **webkit2gtk-4.0**, **libsoup-2.4** y
**libjpeg.so.8**, que Arch ya no trae, y con FreeType reciente puede morir con
SIGSEGV en `TT_New_Context`. Lo estable es correrlo en **Ubuntu 22.04** con
distrobox (comparte `$HOME`, red y pantalla vía XWayland). Compilar y hacer
sideload siguen siendo nativos.

```bash
distrobox create -n ciq -i ubuntu:22.04
distrobox enter ciq -- sudo apt-get update
distrobox enter ciq -- sudo apt-get install -y \
  libwebkit2gtk-4.0-37 libsoup2.4-1 libjpeg-turbo8 libusb-1.0-0 libsecret-1-0 \
  libxxf86vm1 libsm6 libgtk-3-0 openjdk-17-jre-headless

distrobox enter ciq -- env GDK_BACKEND=x11 "$CONNECTIQ_SDK/bin/connectiq" &   # abre el simulador
scripts/build.sh && monkeydo bin/NaNUsage.prg fr955                          # carga la app
```

- Si dentro del contenedor también da SIGSEGV en `TT_New_Context`: copia
  `bin/simulator` y renombra en la copia los símbolos `TT_New_Context` →
  `TZ_New_Context` y `TT_RunIns` → `TZ_RunIns` (mismo largo; evitan que el
  simulador interponga su FreeType interno al del sistema).
- La validación final es siempre en el reloj (datos reales, Comms, consumo).

## 7. Agente local: opencode u omp

Los dos leen [`AGENTS.md`](AGENTS.md) al arrancar: comandos, reglas sobre la
clave y el bucle de prueba en el reloj.

```bash
curl -fsSL https://opencode.ai/install | bash   # opencode
curl -fsSL https://omp.sh/install | sh          # omp (oh-my-pi)
cd ~/code/nan-usage && opencode                 # o: omp
```

Login con tu proveedor: `/connect` (opencode) o `/login` (omp).

- ✅ El agente edita, compila, hace sideload y lee los logs del reloj.
- ❌ No puede pulsar los botones del reloj: la prueba física es tuya; pídele
  qué mirar y luego que lea los logs.
- ❌ No debe abrir `devkey*`/`*.pem`. Aprueba a mano sus comandos de shell.

### Sin conexión (modelo local)

Para vuelos: Ollama (`omarchy pkg add ollama`, `ollama pull <modelo>` **antes**
de salir) y apunta el agente a `http://localhost:11434/v1`.

- **opencode** (`~/.config/opencode/opencode.json`):

  ```json
  {
    "$schema": "https://opencode.ai/config.json",
    "provider": {
      "ollama": {
        "npm": "@ai-sdk/openai-compatible",
        "name": "Ollama (local)",
        "options": { "baseURL": "http://localhost:11434/v1" },
        "models": { "<modelo>": { "name": "<modelo>" } }
      }
    }
  }
  ```

- **omp** (`~/.omp/agent/models.yml`):

  ```yaml
  providers:
    ollama:
      baseUrl: http://localhost:11434/v1
      api: openai-completions
      models:
        - id: <modelo>
          name: <modelo>
  ```

Monkey C es un lenguaje poco común: con modelos pequeños pide cambios acotados
y que consulten la doc offline del SDK (`$CONNECTIQ_SDK/doc/`, `samples/`).

---

## Checklist antes de viajar

- [ ] `scripts/build.sh` compila en el portátil.
- [ ] `devkey.der` presente (600) e ignorado por git; copia de seguridad fuera del portátil.
- [ ] Reloj visto por `mtp-detect` y un sideload completo probado.
- [ ] Cable USB del reloj en la mochila.
- [ ] (opcional) distrobox `ciq` con el simulador abriendo.
- [ ] (opcional) modelo local descargado y probado sin red.
