# SampVoice 3.1 con puerto fijo

Módulo `sampvoice.so` para servidores **SA-MP 0.3.7-R2** en Linux. Lleva dentro el plugin oficial
**SampVoice 3.1** de CyberMor sin modificar y le añade dos cosas:

1. **Puerto de voz fijo**: la voz sale por el puerto que pongas en `server.cfg` (`sv_port`), no por uno aleatorio.
   Funciona en cualquier hosting con Pterodactyl/Wings sin tocar nada del nodo: basta una allocation extra.
2. **Compatible con Pawn.RakNet**: el SampVoice 3.1 oficial hace caer el servidor si se carga junto a
   Pawn.RakNet; este módulo lo evita.

Los jugadores usan el **cliente oficial de SampVoice 3.1** (SA-MP 0.3.7-R1 o R3), sin cambios.

## Instalación

1. Copia `plugins/sampvoice.so` a la carpeta `plugins/` del servidor (sustituye al anterior si lo había).
2. Copia `pawno/include/sampvoice.inc` a tu carpeta de includes (es el include oficial de la 3.1).
3. En `server.cfg`:
   ```
   sv_port 3000
   plugins ... sampvoice.so
   ```
   - `sv_port` es el puerto UDP de la voz. **Tiene que ser distinto** del `port` del juego.
   - En Pterodactyl: añade una allocation al servidor (por ejemplo la 3000) y pon ese número en `sv_port`.
   - Alternativa: la variable de entorno `SV_PORT` (se usa solo si `server.cfg` no tiene `sv_port`).
4. Tu script de voz: puedes usar `filterscripts/voice.pwn` (B = hablar cerca, Z = hablar a todos) o el tuyo.
   **Cárgalo el primero** en la línea `filterscripts`: si otro filterscript devuelve 0 en `OnPlayerConnect`, los
   que van detrás no reciben el evento y la voz no se activa.

## Comprobar que funciona

Al arrancar, `server_log.txt` debe mostrar:

```
[svport] voice port set to 3000/udp from server.cfg
[svport] voice socket bound to 0.0.0.0:3000/udp
[sv:dbg:network:bind] : voice server running on port 3000
```

Si ves `could not bind voice ... falling back to a random port`, el puerto está ocupado o no existe: revisa la
allocation. Si ves `sv_port is not set`, falta la línea en `server.cfg`.

## Jugadores

Cliente oficial SampVoice 3.1:

- SA-MP 0.3.7-R1: https://github.com/CyberMor/sampvoice/releases/download/v3.1/sv_client_037_r1_english.zip
- SA-MP 0.3.7-R3: https://github.com/CyberMor/sampvoice/releases/download/v3.1/sv_client_037_r3_english.zip

Si algo falla en el cliente, su registro está en
`Documentos\GTA San Andreas User Files\sampvoice\svlog.txt`.

## Opciones de `server.cfg`

| Clave | Uso |
|-------|-----|
| `sv_port <puerto>` | Puerto UDP de la voz (1-65535, distinto de `port`) |
| `bind <IPv4>` | Si el servidor lo usa, la voz escucha en esa misma IP (por defecto 0.0.0.0) |

## Requisitos y límites

- Servidor SA-MP **0.3.7-R2-1 para Linux** (el núcleo de SampVoice solo soporta esa versión). No funciona en
  open.mp ni en 0.3DL.
- Solo UDP/IPv4. El jugador tiene que entrar al servidor por la misma IP pública por la que llega la voz
  (lo normal en Pterodactyl).

## Licencias

- SampVoice © 2019 Mor (CyberMor), licencia MIT: ver `LICENSE-sampvoice`.
- Módulo de puerto fijo, licencia MIT: ver `LICENSE`.
