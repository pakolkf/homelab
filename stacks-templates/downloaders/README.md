# downloaders

Clientes P2P: **qui** (UI de qBittorrent) · **qBittorrent** · **transmission** · **aMule**.
Todos en `homelab_web` (acceso vía Traefik; routers en `traefik/dynamic/`).

## Ajustes recomendados (se aplican DENTRO de cada app)

La config de estos clientes la gestiona la propia app (`settings.json`,
`qBittorrent.conf`) y la **reescribe al salir**, por eso **no se versiona aquí**:
`sync_appdata.sh` usa `rsync` y pisaría los cambios de runtime. Aplica estos
ajustes una vez, **con el contenedor parado**:

### transmission — `/config/settings.json`
| Clave | Valor | Motivo |
| --- | --- | --- |
| `encryption` | `2` | requerir cifrado (privacidad / anti-throttling) |
| `watch-dir-enabled` | `false` | `/watch` no se monta; evita el error de inotify |
| `cache-size-mb` | `64` | subir de `4`; mejor E/S, sobre todo si `MEDIA_DIR` es NAS |

### qBittorrent — `/config/qBittorrent/qBittorrent.conf`, sección `[BitTorrent]`
| Clave | Valor | Motivo |
| --- | --- | --- |
| `Session\Encryption` | `1` | requerir cifrado |

## Contraseñas
Ver `.env.example`. Resumen: **transmission** mantiene `USER`/`PASS` en el `.env`
(sin ellos, LSIO desactiva la auth); **aMule** puede borrar `GUI_PWD`/`WEBUI_PWD`
tras el primer arranque (guarda el MD5; si borras la config sin ellas, genera una
aleatoria visible en `docker logs amule`).

## Conectividad (puertos)
Para buena velocidad, reenvía en el router hacia el host (P2P entrantes):
- qBittorrent: `6881` TCP+UDP
- transmission: `51413` TCP+UDP
- aMule: `4662` TCP + `4672` UDP (si no, LowID)

## Limitación por horario
El scheduler de qBittorrent/transmission (límite en horario laboral) es
**intencional**, no un fallo.

## VPN (pendiente)
Patrón previsto a futuro: **gluetun** + clientes vía `network_mode: service:gluetun`
con kill-switch (sin fugas de IP si cae la VPN).
