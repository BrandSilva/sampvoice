# SA-MP Docker Image for Pterodactyl

Custom Docker image for SA-MP 0.3.7 servers on Pterodactyl/Pelican panels with built-in voice port fix for SampVoice.

## The Problem

SampVoice v3.1 hardcodes `bind(port=0)` — the OS picks a random UDP port for voice traffic. In containerized environments, only panel-allocated ports are exposed, so the random port is unreachable. Additionally, SampVoice announces this random port to clients via RakNet `ServerInfoPacket`, so clients try to connect to a port that isn't exposed.

## The Solution

A 32-bit `LD_PRELOAD` hook (`voicefix.so`) intercepts the `bind()` syscall. When SampVoice tries to bind a UDP socket to port 0, the hook forces it to the panel-assigned voice port instead. This means:

1. SampVoice binds directly to the allocated port (e.g., 7070)
2. SampVoice announces the correct port to clients via RakNet
3. Clients connect to the exposed port — voice works

If the hook fails, the entrypoint falls back to a `socat` TCP+UDP proxy.

## Docker Image

```
ghcr.io/brandsilva/samp:latest
```

## Quick Start

1. Import `egg-samp.json` into your Pterodactyl panel
2. Create a server with a primary port (game) and secondary port (voice)
3. Set `VOICE_PORT` to match the secondary allocation
4. Start the server

## Server Variables

| Variable | Default | Description |
|---|---|---|
| `VOICE_PROXY` | `1` | Enable/disable voice fix (1/0) |
| `VOICE_PORT` | `7070` | UDP voice port (must match panel allocation) |
| `SAMPVOICE_URL` | `none` | URL to download SampVoice plugin |
| `INSTALL_MYSQL` | `0` | Auto-install MySQL plugin (1/0) |
| `SERVER_NAME` | `My SA-MP Server` | Server name |
| `RCON_PASS` | `changeme` | RCON password |
| `MAX_PLAYERS` | `50` | Max players |

## Architecture

```
Container starts
      |
      v
LD_PRELOAD loads voicefix.so (32-bit hook)
      |
      v
SA-MP server starts, loads sampvoice.so plugin
      |
      v
SampVoice calls bind(INADDR_ANY, port=0)
      |
      v
Hook intercepts: bind(INADDR_ANY, port=VOICE_PORT) instead
      |
      v
SampVoice announces VOICE_PORT to clients via RakNet
      |
      v
Clients connect to server_ip:VOICE_PORT (exposed by panel)
```

## How It Works

SampVoice v3.1 (`Network::Bind()`) always binds to port 0:
```cpp
bindAddr.sin_port = NULL;  // OS picks random port
```

The `voicefix.so` hook (compiled as i386 ELF to match SA-MP's 32-bit binary) overrides this:
```c
// When UDP socket binds to port 0, redirect to SV_VOICE_PORT
if (sin->sin_port == 0 && type == SOCK_DGRAM) {
    modified.sin_port = htons(VOICE_PORT);
    return real_bind(sockfd, &modified, addrlen);
}
```

After one successful redirect, the hook disables itself (`unsetenv`) to avoid affecting other sockets.

## Building

```bash
cd docker
docker build -t samp:latest .
```

The Dockerfile uses a multi-stage build: an `i386/debian` stage compiles `voicefix.so` as a native 32-bit library, then copies it into the final image.

Push to GHCR happens automatically via GitHub Actions on changes to `docker/`.

## Credits

Built with [Claude Code](https://claude.ai/code) by Anthropic.

## License

MIT
