# CLAUDE.md

## Qué es este repo

`sampvoice.so` para SA-MP 0.3.7-R2 en Linux que envuelve el binario **oficial de SampVoice 3.1** (MIT, de CyberMor)
y le añade dos cosas, sin modificarlo:

- **Puerto de voz fijo**: parchea la GOT del binario oficial para `bind()`, de modo que su socket UDP (que la 3.1 liga
  al puerto 0) quede en el puerto de `sv_port` de `server.cfg` o de la variable `SV_PORT`. El cliente recibe ese
  puerto porque la 3.1 anuncia lo que devuelve `getsockname()`.
- **Compatibilidad con Pawn.RakNet**: parchea también `mprotect()`. La 3.1 deja en solo lectura la página de
  `GetRakServerInterface` de samp03svr tras enganchar; Pawn.RakNet escribe ahí después y el servidor muere con
  SIGSEGV. El parche mantiene la página escribible, como hacía SampVoice 3.0.

El binario oficial va incrustado con `.incbin`, se escribe a un `memfd` y se abre con `dlopen`.

## Estructura

| Ruta | Qué es |
|---|---|
| `plugin/svport.c` | Todo el módulo |
| `plugin/test_config.c`, `plugin/test.sh` | Pruebas del lector de `server.cfg` (CRLF, BOM, líneas largas, `sv_port` = `port`, `SV_PORT`, `bind`…) |
| `plugin/build.sh` | Compila dentro del contenedor i386 |
| `scripts/build.sh` | Orquesta todo: dependencias, pruebas, compilación, paquete |
| `scripts/fetch-deps.sh` | Descarga y verifica por sha256 el núcleo 3.1, el compilador Pawn y los includes de SA-MP |
| `scripts/package.sh` | Arma `dist/sampvoice-port.zip` y las notas de la release |
| `filterscripts/voice.pwn` | Filterscript de ejemplo (B = local, Z = global) |
| `include/sampvoice.inc` | Include oficial de la 3.1 |
| `egg-samp.json` | Egg de Pterodactyl (imagen `ghcr.io/parkervcp/games:samp`) |
| `pterodactyl/install.sh` | Script de instalación del egg (el JSON lo lleva incrustado) |
| `pterodactyl/start.sh` | Arranque con plazo de apagado: sin él, un SA-MP con muchos plugins no termina de apagarse |

## Reglas

1. **Nunca añadir comentarios al código.**
2. La compilación va en `i386/ubuntu:18.04` a propósito: así el binario solo exige GLIBC_2.4 y sirve en hostings
   viejos. No compilar contra glibc nuevas.
3. Toda dependencia descargada se verifica por sha256 antes de usarla.
4. `SVPORT_VERSION` en `plugin/svport.c` manda: `scripts/package.sh` falla si la etiqueta `vX.Y.Z` no coincide.
5. El egg no debe pisar archivos del cliente: instala solo lo que falta.
6. Commits como `Brando Silva <tridentskycompany@gmail.com>`.

## Probar de verdad

Compilar no basta. Antes de publicar una versión, en un servidor de laboratorio:

1. Arrancar con Pawn.RakNet cargado, en los dos órdenes (antes y después de `sampvoice.so`): no debe caerse.
2. Comprobar en el log `voice socket bound to 0.0.0.0:<sv_port>/udp` y `voice server running on port <sv_port>`.
3. Con un jugador y el cliente oficial 3.1: que la tecla de voz active el micrófono y que lleguen paquetes de audio
   al puerto (`tcpdump -n "udp port <sv_port>"`, se ven paquetes de ~300 bytes a ~10/s mientras habla).
4. Casos de fallo: puerto ocupado y `sv_port` ausente. En los dos el servidor debe arrancar igual, avisando en el log.
5. Apagado: parar desde el panel con plugins pesados cargados (FCNPC, PawnPlus, YSF) y comprobar que el contenedor
   sale solo, sin pulsar Kill. Ojo al probar fuera de Docker: bash **ignora SIGINT** en procesos lanzados con `&`,
   así que la trampa de `start.sh` no se instala y parece que no funciona; hay que probarlo en un contenedor.
