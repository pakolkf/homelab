# downloaders

Clientes P2P: **qui** (UI de qBittorrent) · **qBittorrent** · **transmission** · **aMule**,
más **amarr** (conector Torznab de aMule para los *arr). Todos en `homelab_web`
(las WebUI se exponen vía Traefik; routers en `traefik/dynamic/`).

## amarr (aMule -> Servarr)

**No tiene WebUI** (por eso no se le pone router de Traefik ni puerto publicado):
solo expone endpoints Torznab en `:8080`, consumidos por red. Se conecta a aMule
por **EC** (`amule:4712`) con `AMULE_PASSWORD` = la **Remote GUI** de aMule
(`GUI_PWD`), **no** la de la WebUI.

Se añade **directamente en Sonarr/Radarr** (NO en Prowlarr — amarr no es compatible
con Prowlarr):
- Indexador Torznab (en Sonarr/Radarr) → `http://amarr:8080/indexer/amule`
- Download client (en Sonarr/Radarr) → `http://amarr:8080`

`AMULE_FINISHED_PATH` (`/finished`) se monta sobre la carpeta `incoming` de aMule
para que los *arr importen lo terminado. Verifica la conexión con `docker logs amarr`
(si da error de auth → `AMULE_PASSWORD` ≠ `GUI_PWD` real).

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
