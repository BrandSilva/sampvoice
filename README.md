# sampvoice-port — SampVoice 3.1 con puerto de voz fijo

Módulo para servidores **SA-MP 0.3.7-R2 en Linux** que hace dos cosas que el SampVoice oficial no hace:

1. **La voz sale por el puerto que tú decidas** (`sv_port` en `server.cfg`), no por uno aleatorio. Con eso funciona
   en cualquier hosting con Pterodactyl/Wings: basta una allocation extra, sin tocar nada del nodo.
2. **Convive con Pawn.RakNet.** SampVoice 3.1 tumba el servidor al arrancar si Pawn.RakNet está cargado; este
   módulo lo evita.

Los jugadores no cambian nada: usan el **cliente oficial de SampVoice 3.1** (SA-MP 0.3.7-R1 o R3).

## Instalación rápida

1. Descarga `sampvoice-port.zip` de [Releases](https://github.com/BrandSilva/sampvoice/releases) y descomprímelo
   en la carpeta del servidor.
2. En `server.cfg`:
   ```
   sv_port 3000
   filterscripts voice
   plugins sampvoice.so
   ```
   `sv_port` es el puerto UDP de la voz y **tiene que ser distinto del `port` del juego**. En Pterodactyl, añade una
   allocation al servidor y pon aquí ese número.
3. Arranca. En el log debe salir:
   ```
   [svport] voice port set to 3000/udp from server.cfg
   [svport] voice socket bound to 0.0.0.0:3000/udp
   [sv:dbg:network:bind] : voice server running on port 3000
   ```

El filterscript de ejemplo (`voice.amx`) da **B** para hablar cerca y **Z** para hablar a todos. **Cárgalo el primero**
en `filterscripts`: si otro filterscript devuelve 0 en `OnPlayerConnect`, los que van detrás no reciben el evento y la
voz no se activa nunca. Si tu gamemode ya gestiona la voz, no uses el de ejemplo.

Instrucciones completas para el dueño del servidor: `sampvoice-port/LEEME.md` dentro del zip.

## Egg de Pterodactyl

`egg-samp.json` instala SA-MP 0.3.7-R2-1 y este módulo sobre la imagen estándar `ghcr.io/parkervcp/games:samp`.
Variables: `SV_PORT` (el puerto de voz), `INSTALL_VOICE`, `VOICE_FILTERSCRIPT` y `SVPORT_VERSION`. La instalación es
idempotente: no pisa `server.cfg`, gamemodes ni filterscripts que ya existan.

## Cómo funciona

`sampvoice.so` de este repo es un envoltorio que lleva dentro el binario **oficial** de SampVoice 3.1 (MIT, de
[CyberMor](https://github.com/CyberMor/sampvoice)) sin modificar. Al cargarse:

1. Escribe el binario oficial en un `memfd` (si no puede, en un temporal) y lo abre con `dlopen`.
2. Redirige en su GOT dos funciones:
   - **`bind`** — SampVoice 3.1 liga su socket UDP al puerto 0, y luego anuncia al cliente el puerto que le dio el
     sistema (`getsockname`). El módulo lo liga al puerto de `sv_port`, así que el cliente recibe ese puerto.
   - **`mprotect`** — SampVoice 3.1 engancha `GetRakServerInterface` de samp03svr y deja esa página de código como
     solo lectura. Pawn.RakNet escribe después en la misma página dando por hecho que sigue escribible, y el
     servidor muere con SIGSEGV. El módulo mantiene la página escribible, que es como se comporta SampVoice 3.0.
3. Reenvía `Supports`, `Load`, `Unload`, `AmxLoad`, `AmxUnload` y `ProcessTick` al binario oficial.

Si el puerto está ocupado o no se configuró, el módulo avisa en el log y deja que la voz use un puerto aleatorio: el
servidor nunca se queda sin arrancar por esto.

## Opciones

| `server.cfg` | Uso |
|---|---|
| `sv_port <puerto>` | Puerto UDP de la voz (1-65535, distinto de `port`) |
| `bind <IPv4>` | Si el servidor usa una IP concreta, la voz escucha en esa misma IP |

Si `server.cfg` no trae `sv_port`, se usa la variable de entorno `SV_PORT`.

## Compilar

Necesitas Docker (la compilación va en un contenedor i386 con glibc antigua, para que el binario sirva en cualquier
hosting: solo exige GLIBC_2.4).

```bash
./scripts/build.sh     # descarga dependencias, pasa las pruebas, compila y arma dist/sampvoice-port.zip
```

Las dependencias que descarga (SampVoice 3.1 oficial, compilador Pawn e includes de SA-MP) se verifican por sha256.

## Límites

- Solo **SA-MP 0.3.7-R2 en Linux** (probado con R2-1 y R2-2-1). No funciona en open.mp ni en 0.3DL: es una
  limitación del propio SampVoice, que engancha direcciones fijas del servidor.
- Solo UDP/IPv4.
- Los clientes 3.1 y 4.x no son compatibles entre sí; este módulo es de la rama 3.1.

## Licencias

- Este módulo: MIT (`LICENSE`).
- SampVoice © 2019 Mor (CyberMor), MIT (`LICENSE-sampvoice`). El binario oficial se redistribuye dentro del módulo
  sin modificarlo.
