# downloaders

Clientes P2P: **qBittorrent** · **transmission** · **aMule** + **amutorrent**
(frontend unificado que se integra con los *arr y aMule por EC). Todos en
`homelab_web`; las WebUI se exponen vía Traefik (routers en `traefik/dynamic/`).

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
| `port-forwarding-enabled` | `false` | UPnP off; Docker ya publica `51413` |
| `ratio-limit` | `2.0` | seedear hasta ratio 2 antes de parar |
| `ratio-limit-enabled` | `true` | activa el tope anterior |

### qBittorrent — `/config/qBittorrent/qBittorrent.conf`, sección `[BitTorrent]`
| Clave | Valor | Motivo |
| --- | --- | --- |
| `Session\Encryption` | `1` | requerir cifrado |
| `Session\GlobalMaxRatio` | `2.0` | tope de ratio (con `0` se para al instante de terminar) |
| `Session\MaxRatioAction` | `0` | `0` = pausar al alcanzar ratio (no borrar) |

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

## Limitación por horario (scheduler de ancho de banda)

**Ambos clientes traen activo un *scheduler* que reduce el BW en horario laboral
Lun-Vie 07:00–18:00.** Es intencional, no un fallo. Mecánica:

### qBittorrent — `qBittorrent.conf`, sección `[BitTorrent]` + `[Preferences]`
| Clave | Valor actual | Significado |
| --- | --- | --- |
| `Session\BandwidthSchedulerEnabled` | `true` | activa el scheduler |
| `Session\AlternativeGlobalDLSpeedLimit` | `48828` | límite **descarga** en KB/s mientras está activa la franja (≈48 MB/s) |
| `Session\AlternativeGlobalUPSpeedLimit` | `48828` | límite **subida** en KB/s en franja |
| `Session\UseAlternativeGlobalSpeedLimit` | `true` | ⚠️ **fuerza el modo "alt-speed" SIEMPRE**, ignorando el scheduler. Si quieres que el scheduler decida, ponlo a `false`. |
| `Scheduler\days` | `Weekday` | días activos (`Weekday` = Lun-Vie; otras: `Everyday`, `Weekend`, `MonTuesWedThursFri`, días sueltos) |
| `Scheduler\start_time` / `Scheduler\end_time` | binario Qt-encoded | horario; se edita más cómodo desde la WebUI (Tools → Options → Speed → Scheduler) |

> Para **quitar** el scheduler en qBittorrent: pon `Session\BandwidthSchedulerEnabled=false` **y** `Session\UseAlternativeGlobalSpeedLimit=false`.

### transmission — `/config/settings.json`
| Clave | Valor actual | Significado |
| --- | --- | --- |
| `alt-speed-time-enabled` | `true` | activa el scheduler de "alt-speed" |
| `alt-speed-time-begin` | `420` | inicio en minutos desde 00:00 → `420` = **07:00** |
| `alt-speed-time-end` | `1080` | fin en minutos → `1080` = **18:00** |
| `alt-speed-time-day` | `62` | bitmask de días. `62` = Lun-Vie (`SUN=1, MON=2, TUE=4, WED=8, THU=16, FRI=32, SAT=64`; `2+4+8+16+32=62`). `127` = todos los días, `65` = sólo fin de semana. |
| `alt-speed-down` | `40000` | descarga en KB/s durante la franja (≈40 MB/s) |
| `alt-speed-up` | `40000` | subida en KB/s durante la franja |
| `alt-speed-enabled` | `false` | si lo pones `true`, fuerza alt-speed SIEMPRE (ignora el scheduler) — equivalente al `UseAlternativeGlobalSpeedLimit` de qBittorrent |

> Para **quitar** el scheduler en transmission: pon `alt-speed-time-enabled=false`. Para desactivar también el modo manual: `alt-speed-enabled=false`.

> Importante: edita estos valores con **el contenedor parado** (ambas apps reescriben su conf al salir). `docker stop <svc>` → editar → `docker start <svc>`.
