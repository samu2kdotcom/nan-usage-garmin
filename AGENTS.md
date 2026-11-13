# AGENTS.md — contexto para agentes de código (opencode, omp, …)

**NaN Usage**: widget Garmin Connect IQ (Monkey C) que muestra el consumo de
créditos de NaN Cloud. Responde en español. Entorno local y reloj por USB:
[`DESARROLLO.md`](DESARROLLO.md).

## Estructura

- `manifest.xml` — productos (`<iq:product>`) y `minApiLevel` (filtro real de compatibilidad).
- `source/*.mc` — app, vistas (glance, principal, desglose) y `QuotaStore`.
- `resources/` — strings, drawables, propiedades y settings.
- `scripts/build.sh`, `scripts/sideload.sh` — compilar y copiar al reloj.
- `bin/` — salida de compilación (ignorada).

## Comandos

```bash
scripts/build.sh                              # fr955 -> bin/NaNUsage.prg
scripts/build.sh fr265                        # otro modelo del manifest
scripts/sideload.sh bin/NaNUsage.prg          # copia al reloj por MTP (si está conectado)
scripts/sideload.sh --logs-on bin/NaNUsage.prg
scripts/sideload.sh --pull-logs /tmp/ciq-logs # println y CIQ_LOG.YML del reloj
monkeydo bin/NaNUsage.prg fr955               # solo si el simulador está abierto
```

- Verificación mínima de un cambio de código: `scripts/build.sh` termina en
  `BUILD SUCCESSFUL` sin warnings nuevos. Si tocas layouts, compila también
  los modelos afectados del manifest (resoluciones distintas).
- Si falla por SDK, Java o dispositivo ausente, dilo al usuario: no cambies
  rutas en los scripts.
- API de Toybox: consulta `$CONNECTIQ_SDK/doc/` y `$CONNECTIQ_SDK/samples/`
  antes de suponerla. Límites del dispositivo (memoria, resolución, API level):
  `~/.Garmin/ConnectIQ/Devices/<deviceId>/compiler.json`.

## Prueba en el reloj

El agente no puede pulsar botones del reloj. Bucle: compilar →
`scripts/sideload.sh` → pedir al usuario que desconecte el cable y pruebe X →
cuando reconecte, `--pull-logs` y analizar. Un crash muestra "IQ!" y deja la
pila en `GARMIN/APPS/LOGS/CIQ_LOG.YML`.

## Reglas (no negociables)

- **Nunca** leer, imprimir, copiar ni versionar `devkey*`, `*.der`, `*.pem`,
  `developer_key*`, `devcert*`. Los scripts los usan por ruta.
- **Nunca** escribir una API key real en `resources/properties/properties.xml`
  ni en ningún fichero versionado, ni imprimirla.
- `*.prg`, `*.iq`, `bin/`, `exports/` jamás en git. Un `.prg` con la key
  horneada es solo para el reloj de quien lo compila.
- Antes de un commit: `git status` sin claves ni binarios.
