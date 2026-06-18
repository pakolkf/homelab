# Homelab

Homelab autoalojado sobre **Docker** en un host Linux (Ubuntu/Debian), con bootstrap automatizado del sistema, DNS recursivo propio, reverse proxy con TLS automático y un catálogo de servicios habituales (dashboard, gestor de ficheros, backups, monitorización, VPN…).

La gestión es **dockhand-first**: por terminal solo se instalan `hawser` y `dockhand`; **todo lo demás se despliega y configura desde la UI de dockhand**. Este repositorio es la **fuente de verdad** de las recetas y la config; todo vive en `/opt/homelab/` del host.

---

## Tabla de contenidos

- [Requisitos](#requisitos)
- [Modelo de despliegue (dockhand-first)](#modelo-de-despliegue-dockhand-first)
- [Estructura del repositorio](#estructura-del-repositorio)
- [Instalación rápida](#instalación-rápida)
- [Añadir un host adicional (solo hawser)](#añadir-un-host-adicional-solo-hawser)
- [Red entre hosts (apps en hosts remotos)](#red-entre-hosts-apps-en-hosts-remotos)
- [Arquitectura](#arquitectura)
- [Servicios incluidos](#servicios-incluidos)
- [Authentik — SSO y autenticación centralizada](#authentik--sso-y-autenticación-centralizada)
- [Configuración previa en Cloudflare](#configuración-previa-en-cloudflare)
- [Operación habitual](#operación-habitual)
- [Añadir un servicio nuevo](#añadir-un-servicio-nuevo)
- [Seguridad y permisos](#seguridad-y-permisos)
- [Tareas programadas (cron)](#tareas-programadas-cron)

---

## Requisitos

- Host con **Ubuntu / Debian** (los scripts usan `apt-get` y `systemd-resolved`).
- Acceso `root` (vía `sudo`).
- Red del host: ajusta `scripts/set_ip.sh` (`INTERFACE`, `STATIC_IP`, `GATEWAY`) a tu LAN **antes** del bootstrap — `init.sh` lo aplica con IP estática.
- Dominio propio gestionado en **Cloudflare** (necesario para el reto DNS-01 de Let's Encrypt). El dominio y el email ACME se definen **solo** en `docker/.env` (`FQDN`, `ACME_EMAIL`); los configs (`traefik.yaml`, `dynamic/`, `unbound.conf`) usan `${FQDN}` / `${ACME_EMAIL}` y los renderiza `sync_appdata.sh` al copiarlos a `appdata`.
- Conectividad saliente a los registros de imagen y a Let's Encrypt.

Docker y Docker Compose **no** son requisitos previos: los instala `scripts/install_docker.sh`.

---

## Modelo de despliegue (dockhand-first)

**Solo `hawser` y `dockhand` se instalan por terminal** (`docker compose up`, tras el bootstrap del host). El resto de servicios se instalan y configuran **desde la UI de dockhand**, que los gestiona como stacks y los ejecuta a través del agente `hawser`.

Tres árboles en el host:

| Ruta | Qué contiene | Quién la gestiona |
| --- | --- | --- |
| `/opt/homelab/docker/` | Bootstrap: `hawser`, `dockhand` y el `.env` del host | Tú, por terminal |
| `/opt/homelab/stacks/<stack>/` | Runtime de **hawser** de este host (los compose que ejecuta) | hawser (`STACKS_DIR`) |
| `/opt/homelab/appdata/dockhand/stacks/{env}/{stack}/` | Copia central de los stacks de **todos** los environments | dockhand (interno, estructura impuesta) |
| `/opt/homelab/appdata/<svc>/` | Config + datos de cada servicio | `sync_appdata.sh` (config) + runtime (datos) |

- **Recetas en el repo:** las plantillas viven en `stacks-templates/<svc>/` y son la fuente para crear los stacks en dockhand. Al desplegar, dockhand guarda la **copia central** en `/opt/homelab/appdata/dockhand/stacks/{env}/{stack}/` (todos los environments, su almacén interno) y **hawser** escribe/ejecuta el **runtime** en su `STACKS_DIR` = `/opt/homelab/stacks/<stack>/` (plano, por host). Los stacks de Git van a `/opt/homelab/appdata/dockhand/git-repos/{env}/{stack}/`.
- **Datos y config en appdata:** los volúmenes apuntan a `${APPDATA_DIR}` (= `/opt/homelab/appdata/<svc>`, ruta absoluta). La config versionada (p.ej. `traefik.yaml`, `dynamic/`, `unbound.conf`, `AdGuardHome.yaml`) la copia ahí `scripts/sync_appdata.sh` desde el repo, porque dockhand solo escribe el `compose`. Al copiarla, `sync_appdata.sh` **renderiza** `${FQDN}` y `${ACME_EMAIL}` con los valores del `.env` del host, así el repo nunca contiene el dominio ni el email reales.
- **Rescate sin UI:** si dockhand cae, basta SSH al host y `docker compose` a mano sobre la receta en `/opt/homelab/stacks/...` (o copiar lo que haga falta a `appdata`).

### Convención de `.env` y variables

Cada compose gestionado por dockhand carga **dos** ficheros de entorno y usa una variable por stack para los volúmenes:

```yaml
env_file:
  - /opt/homelab/docker/.env   # del HOST: PUID/PGID/TZ/APPDATA… (lo monta hawser)
  - .env                        # del STACK: secretos/config (lo gestiona dockhand)
volumes:
  - ${APPDATA_DIR}/data:/data   # APPDATA_DIR=/opt/homelab/appdata/<svc> (en el .env del stack)
```

- `/opt/homelab/docker/.env` es **local a cada host** (mismo path, contenido propio): `create_estructure.sh` autodetecta `PUID/PGID` del usuario real (`${SUDO_UID:-$(id -u)}`). `hawser` lo monta en `:ro` y, como ejecuta el compose en el host destino, cada host inyecta sus propios uids — clave para hosts remotos con uid distinto.
- `APPDATA_DIR` es **una sola variable por stack** (ruta absoluta). Mover los datos de un servicio = cambiar esa línea en el `.env` del stack.
- Las rutas de volúmenes son **absolutas** porque `hawser` ejecuta en el host destino (las relativas no valen en hosts remotos).
- Cada stack incluye un **`.env.example`** versionado (sin secretos) con sus variables; al crearlo en dockhand, cópialo a su `.env` y rellena (`APPDATA_DIR` + secretos). Evita la deriva de variables.

---

## Estructura del repositorio

```
.
├── docker/                      Bootstrap por terminal (solo estos)
│   ├── .env                     Variables del host (PUID/PGID/TZ/APPDATA/STACKS_BASE…)
│   ├── hawser/                  Agente de escritura de dockhand (socket rw + STACKS_DIR)
│   └── dockhand/                Gestor visual de stacks
├── stacks-templates/            Recetas de los stacks que gestiona dockhand
│   ├── adguard/                 DNS con filtrado
│   ├── authentik/               SSO / proveedor de identidad
│   ├── beszel/                  Monitorización ligera
│   ├── cloudflare/              Cloudflare Tunnel + companion para Traefik
│   ├── downloaders/            qbittorrent + transmission + amule + amutorrent (clientes P2P)
│   ├── dozzle/                  Logs de contenedores en vivo
│   ├── duplicati/               Backups
│   ├── filebrowser/             Explorador de ficheros web
│   ├── homarr/                  Dashboard principal
│   ├── indexers/               flaresolverr + jackett + prowlarr (indexadores)
│   ├── nutify/                  Notificaciones / monitor UPS
│   ├── socket-proxy/            Proxy read-only al socket Docker
│   ├── tailscale/               VPN mesh (network_mode: host)
│   ├── traefik/                 Reverse proxy + TLS (Let's Encrypt)
│   ├── unbound/                 DNS recursivo (DNSSEC)
│   ├── uptime-kuma/             Monitorización de uptime
│   ├── vaultwarden/             Gestor de contraseñas (Bitwarden compat.)
│   └── wgdashboard/             Panel WireGuard
└── scripts/                     Scripts de bootstrap del host
    ├── init.sh                  Orquestador (lanza todo lo demás en orden)
    ├── auto_update.sh           Cron diario apt-get upgrade
    ├── set_ip.sh                IP estática del host (netplan)
    ├── update_unbound_stack.sh  Cron periódico: pull de imagen + recreate de unbound (refresca raíces)
    ├── disable_ipv6.sh          Desactiva IPv6 (sysctl)
    ├── disable_dns.sh           Libera el puerto 53 (stub de systemd-resolved)
    ├── enable_firewall.sh       UFW: deny incoming + allow 22/tcp (SSH), 80/tcp, 443/tcp
    ├── fix_unmask.sh            umask 027 para el usuario
    ├── create_estructure.sh     Crea /opt/homelab/{docker,stacks,appdata} y el .env del host
    ├── fix_overcommit.sh        sysctl vm.overcommit_memory (Redis de Homarr)
    ├── sync_appdata.sh          Copia la config versionada a /opt/homelab/appdata
    ├── fix_permissions.sh       Refuerza propietario y modos
    ├── install_docker.sh        Instala Docker Engine + Compose plugin
    └── create_docker_network.sh Crea las 3 redes externas del homelab
```

En tiempo de ejecución, el host además tiene `/opt/homelab/stacks/` (runtime que ejecuta hawser en este host) y `/opt/homelab/appdata/` (config + datos), que **no** están en el repo. Las copias centrales de las recetas (todos los environments) viven en `/opt/homelab/appdata/dockhand/stacks/`.

---

## Instalación rápida

1. Clona o copia este repositorio en el host (ej. `/root/homelab`).

   > ⚠️ **Antes de continuar**, edita `scripts/set_ip.sh` con los valores de **tu** red (`INTERFACE`, `STATIC_IP`, `GATEWAY`). `init.sh` lo ejecuta con `static`; con los valores por defecto (`eth0`, `192.168.1.100/24`, gw `192.168.1.1`) podrías cambiar o perder la IP del host.

2. Ejecuta el bootstrap completo (idempotente):

   ```bash
   sudo ./scripts/init.sh
   ```

   Deja el sistema preparado: actualizado, IP estática, sin IPv6, DNS del host configurado, **UFW activo** (SSH `22/tcp`, HTTP `80/tcp`, HTTPS `443/tcp`; resto denegado), `/opt/homelab/{docker,stacks,appdata}` creado, Docker instalado, las redes `homelab_web`, `homelab_socket` y `homelab_dns` creadas, y la config versionada copiada a `appdata` (`sync_appdata.sh`).

3. Copia el bootstrap a `/opt/homelab/docker/` y crea sus `.env`:

   ```bash
   # --exclude '.env': preserva el .env que generó init.sh con tus PUID/PGID
   # autodetectados (y los .env por-stack); el rsync NO los pisa.
   sudo rsync -a --exclude '.env' ./docker/ /opt/homelab/docker/
   # crea /opt/homelab/docker/hawser/.env y /opt/homelab/docker/dockhand/.env (600, root)
   sudo ./scripts/fix_permissions.sh
   ```

   - `hawser/.env`: `PORT=2376`, `STACKS_DIR=/opt/homelab/stacks`, `TOKEN=<token>` (genéralo con `openssl rand -base64 32`).
   - `dockhand/.env`: `HOST_DATA_DIR=/opt/homelab/appdata/dockhand` (dónde está su `/app/data`). Ya no usa `STACK_DIR`.
   - `docker/.env` (ya lo generó `init.sh` con tus `PUID`/`PGID` reales — el rsync no lo toca): edita `FQDN` y `ACME_EMAIL` y reejecuta `sudo ./scripts/sync_appdata.sh` para renderizar la config.

4. Levanta `hawser` y `dockhand` por terminal:

   ```bash
   cd /opt/homelab/docker/hawser   && docker compose up -d
   cd /opt/homelab/docker/dockhand && docker compose up -d
   ```

5. Entra en dockhand (`http://<IP_LAN>:8085`) y:
   - Registra el host: **Settings → Environments → Add** → *Hawser*, URL `http://hawser:2376`, con el `TOKEN` de `hawser/.env`.
   - Crea cada stack a partir de su receta en `stacks-templates/<svc>/`, definiendo en el `.env` del stack `APPDATA_DIR=/opt/homelab/appdata/<svc>` y sus secretos.
   - Orden recomendado: `socket-proxy` → `unbound` → `adguard` → `traefik` (+ `error-pages`) → resto.

   > Cada host nuevo que añadas necesita su `/opt/homelab/docker/.env` (lo genera `init.sh`/`create_estructure.sh` con sus propios uids) y `hawser` instalado allí.

---

## Añadir un host adicional (solo hawser)

Para sumar otro host (p.ej. `pve01`, `raspi01`) que ejecute stacks gestionados desde el dockhand central, ese host corre **solo el agente `hawser`** (no dockhand). dockhand lo controla por red.

1. **Red del host:** edita `scripts/set_ip.sh` a tu LAN si vas a fijar IP en este host (igual que en el principal).

2. **Bootstrap reducido** (sin las partes de DNS/IPv6 del host DNS principal). Clona el repo y ejecuta solo lo necesario:

   ```bash
   sudo ./scripts/install_docker.sh         # Docker + Compose
   sudo ./scripts/create_docker_network.sh  # redes homelab_web/socket/dns
   sudo ./scripts/create_estructure.sh      # /opt/homelab/{docker,stacks,appdata} + .env del host (PUID/PGID autodetectados)
   sudo ./scripts/sync_appdata.sh           # solo si aquí corren stacks con config versionada (traefik/unbound/adguard)
   sudo ./scripts/fix_permissions.sh
   ```
   > `init.sh` completo además fija IP estática, desactiva IPv6/DNS y mete el cron de unbound — eso es del host DNS principal. En un host solo-apps ejecútalo solo si te aplica. Si aquí corren traefik/dns, edita `docker/.env` (`FQDN`/`ACME_EMAIL`) antes de `sync_appdata.sh`.

3. **Instala hawser (no dockhand).** A diferencia del host principal (donde dockhand lo alcanza por la red interna), aquí hawser debe **publicar su puerto** para que el dockhand central llegue por IP:

   ```bash
   sudo rsync -a --exclude '.env' /ruta/a/tu/clon/docker/hawser /opt/homelab/docker/
   ```
   Crea `/opt/homelab/docker/hawser/.env` (600, root):
   ```ini
   PORT=2376
   STACKS_DIR=/opt/homelab/stacks
   TOKEN=<token-de-este-host>      # openssl rand -base64 32
   ```
   En `/opt/homelab/docker/hawser/docker-compose.yaml`, **publica el puerto** (añade bajo el servicio `hawser`):
   ```yaml
       ports:
         - "2376:2376"
   ```
   ```bash
   cd /opt/homelab/docker/hawser && docker compose up -d
   ```
   > Expón `2376` solo en red de confianza (LAN o **Tailscale**); la autenticación es el `TOKEN`.

4. **Registra el environment en el dockhand central:**
   - **Settings → Environments → Add → Hawser**
   - URL: `http://<IP-de-este-host>:2376` (IP LAN o Tailscale)
   - Token: el `TOKEN` de `hawser/.env` de este host.

5. Crea/despliega stacks en ese environment desde la UI. El **runtime** irá a `/opt/homelab/stacks/<stack>/` **en este host**; la **copia central** queda en el dockhand principal (`/opt/homelab/appdata/dockhand/stacks/{env}/{stack}/`).

---

## Red entre hosts (apps en hosts remotos)

Las redes Docker (`homelab_web`, etc.) son **locales a cada host**: un contenedor en `pve01` **no** está en la `homelab_web` del host principal. Por eso el traefik central solo puede enrutar por nombre de contenedor (`http://servicio:puerto`) a servicios **del mismo host**. Para apps en otros hosts hay que alcanzarlas por **IP del host remoto + puerto publicado** (por **LAN** de momento; **Tailscale** queda pendiente, ver abajo).

1. En el host remoto, el stack de la app **publica su puerto** (p.ej. `ports: ["8222:80"]`), accesible por la **IP LAN** del host.
2. En el **traefik central**, el router dinámico de ese servicio apunta a la IP del host remoto en vez de al nombre de contenedor:

   ```yaml
   http:
     routers:
       vaultwarden:
         rule: "Host(`vault.${FQDN}`)"
         entryPoints: [websecure]
         service: vaultwarden
         middlewares: [secure-headers, error-pages]
         tls: { certResolver: cloudflare }
     services:
       vaultwarden:
         loadBalancer:
           servers:
             - url: "http://<ip-lan-de-pve01>:8222"
   ```

3. Camino externo completo: **Cloudflare → túnel → traefik central → (LAN) → app en el host remoto**.

Notas:
- Apps en el **mismo host** que traefik siguen usando el nombre de contenedor (`http://servicio:puerto`) por `homelab_web` — no necesitan publicar puerto.
- Docker no hace red multi-host sin Swarm/overlay; por eso el patrón es IP+puerto.
- **Tailscale (pendiente):** cuando lo integres, sustituyes la IP LAN por la IP Tailscale del host (IPs estables + malla cifrada, ideal si los hosts no comparten LAN). Lo documentamos al añadirlo.
- Alternativa (más compleja): que cada host tenga su propio traefik expuesto por su propio túnel Cloudflare.

---

## Arquitectura

### Tres redes Docker externas

Todas se crean en `scripts/create_docker_network.sh` y los compose se conectan a ellas como `external: true`:

| Red | Para qué sirve |
| --- | --- |
| `homelab_web` | Tráfico HTTP/HTTPS que pasa por Traefik. |
| `homelab_socket` | Plano del socket Docker: lectura vía `socket-proxy-ro`; `hawser` es la única excepción con socket crudo (rw). |
| `homelab_dns` | Plano DNS interno (AdGuard ↔ Unbound). |

### Cadena DNS

```
clientes → AdGuard (53, filtrado) → Unbound (5335, recursivo + DNSSEC) → raíz
```

`scripts/disable_dns.sh` libera el puerto 53 desactivando el stub listener de `systemd-resolved`. Un cron periódico (`scripts/update_unbound_stack.sh`) re-despliega el stack de Unbound para mantener las raíces al día (ver abajo).

### Raíces de Unbound (`root.hints` / ancla DNSSEC)

**Las gestiona la propia imagen `klutchell/unbound`, no nosotros.** Trae `root.hints` y el ancla DNSSEC *baked* (en `/var/unbound`), y unbound mantiene el ancla **al día en runtime** vía `auto-trust-anchor-file` (RFC5011). Por eso **no** montamos ni declaramos `root-hints`/`trust-anchor-file` en `unbound.conf` (duplicarlos da *"presented twice"* / *"second hints ignored"*).

El único caso en que las raíces baked se quedarían atrás es si nunca se actualiza la imagen. Para evitarlo:

- **`scripts/update_unbound_stack.sh`** instala un cron (por defecto mensual, día 1 a las 04:00 → `/etc/cron.d/homelab-unbound-update`, log en `/var/log/homelab-unbound.log`). El cron hace `docker pull klutchell/unbound:latest` y **recrea** el contenedor con su mismo compose (localizado por las labels de compose del propio contenedor), trayendo `root.hints` frescos, ancla actualizada y parches de unbound.
- Ajusta la frecuencia editando `CRON_SCHEDULE` en el script.

Para forzar una actualización a mano:

```bash
sudo /ruta/al/repo/scripts/update_unbound_stack.sh --run
```
> Si el contenedor no se desplegó vía `docker compose` (sin labels), el script avisa y solo reinicia; en ese caso re-despliega el stack `unbound` desde dockhand para aplicar la imagen nueva.

### Socket de Docker: socket-proxy-ro + hawser

Ningún servicio expuesto monta `/var/run/docker.sock` directamente.

- **Lectura:** `socket-proxy-ro` (read-only, expone solo PING/VERSION/EVENTS/CONTAINERS/NETWORKS) por `tcp://socket-proxy-ro:2375` en `homelab_socket`. Lo usan Traefik, dozzle, beszel, cloudflare-companion y homarr.
- **Escritura:** `hawser`, el agente de dockhand. Es el único contenedor que monta el socket crudo (rw); dockhand habla con él por token (`http://hawser:2376`). No hay un `socket-proxy` read-write.

### Traefik

- Configuración estática: `traefik.yaml` (entrypoints, providers, ACME).
- Configuración dinámica (rutas/middlewares): `dynamic/*.yaml` (file-provider).
- En el repo viven en `stacks-templates/traefik/`; en el host se montan desde `/opt/homelab/appdata/traefik/` (las copia `sync_appdata.sh`).
- TLS automático con **Let's Encrypt**, reto **DNS-01 contra Cloudflare**.
- Dos resolvers: `letsencrypt-staging` (por defecto) y `letsencrypt-production`. Cambia el resolver activo en `entryPoints.websecure` cuando todo funcione en staging.
- Páginas de error servidas por `tarampampam/error-pages` (router catch-all `error-pages-fallback`).
- Cabeceras seguras por defecto vía middleware `secure-headers` (HSTS, X-Frame-Options, CSP, etc.).

---

## Servicios incluidos

Bootstrap (por terminal):

| Stack | Imagen | Puerto host | Función |
| --- | --- | --- | --- |
| hawser | `ghcr.io/finsys/hawser` | — (interno 2376) | Agente de escritura de dockhand (socket rw) |
| dockhand | `fnsys/dockhand` | 8085 | Gestor visual de stacks |

Gestionados por dockhand:

Convención de la columna **Puerto host**:
- `—` → solo accesible vía Traefik por FQDN (no publica al host).
- `80, 443` → entrypoints de Traefik.
- `53/tcp+udp` (AdGuard) → servicio DNS para los clientes LAN.
- `51820/udp` (WireGuard), `6881`, `51413`, `4662/4665/4672` → tráfico P2P o de VPN externo, **no** UI.
- `8054`, `9000/9443` → acceso LAN directo de **rescate** (cuando DNS/Traefik no responden). Quítalos si no los necesitas.

| Stack | Imagen | Puerto host | Función |
| --- | --- | --- | --- |
| traefik | `traefik:latest` | 80, 443 | Reverse proxy + TLS automático |
| error-pages | `tarampampam/error-pages` | — | Páginas de error personalizadas |
| socket-proxy | `lscr.io/linuxserver/socket-proxy` | — (interno 2375, read-only) | Acceso de solo lectura al socket Docker |
| unbound | `klutchell/unbound` | — (interno 5335) | DNS recursivo con DNSSEC |
| adguard | `adguard/adguardhome` | 53/tcp+udp, 8054 *(rescate)* | DNS con filtrado de anuncios |
| homarr | `ghcr.io/homarr-labs/homarr` | — | Dashboard del homelab |
| dozzle | `amir20/dozzle` | — | Logs en vivo de contenedores |
| beszel | `henrygd/beszel` | — | Métricas de servidores |
| uptime-kuma | `louislam/uptime-kuma` | — | Monitor de uptime |
| nutify | `dartsteven/nutify` | — | Notificaciones / UPS |
| filebrowser | `filebrowser/filebrowser` | — | Navegador web de ficheros |
| duplicati | `lscr.io/linuxserver/duplicati` | — | Backups |
| vaultwarden | `vaultwarden/server` | — | Gestor de contraseñas |
| wgdashboard | `ghcr.io/wgdashboard/wgdashboard` | 51820/udp | Panel WireGuard (UI vía Traefik; UDP para el túnel) |
| indexers · flaresolverr | `ghcr.io/flaresolverr/flaresolverr` | — (interno 8191) | Resolutor de retos Cloudflare para los indexadores |
| indexers · jackett | `lscr.io/linuxserver/jackett` | — | Indexador de torrents/usenet |
| indexers · prowlarr | `lscr.io/linuxserver/prowlarr` | — | Gestor de indexadores (integra con *arr) |
| downloaders · qbittorrent | `lscr.io/linuxserver/qbittorrent` | 6881/tcp+udp | Cliente BitTorrent (UI vía Traefik; TCP/UDP para peers) |
| downloaders · transmission | `lscr.io/linuxserver/transmission` | 51413/tcp+udp | Cliente BitTorrent (UI vía Traefik; TCP/UDP para peers) |
| downloaders · amule | `ngosang/amule` | 4662/tcp, 4665/udp, 4672/udp | Cliente ED2K/Kademlia (UI vía Traefik; TCP/UDP para la red eD2K) |
| downloaders · amutorrent | `g0t3nks/amutorrent` | — | Frontend unificado para los clientes |
| tailscale | `tailscale/tailscale` | host network | VPN mesh |
| authentik | `ghcr.io/goauthentik/server` | 9000, 9443 *(rescate)* | SSO / proveedor de identidad |
| cloudflare-tunnels | `cloudflare/cloudflared` | — | Túnel Cloudflare |
| cloudflare-companion | `tiredofit/docker-traefik-cloudflare-companion` | — | Sincroniza routers de Traefik con DNS de Cloudflare |

---

## Authentik — SSO y autenticación centralizada

Authentik actúa como proveedor de identidad (IdP) para el homelab. Se usa el modo **Proxy Provider + ForwardAuth de Traefik**: Traefik intercepta cada petición antes de que llegue al servicio y consulta a Authentik. Si no hay sesión válida, redirige al login.

> **Nota de versión:** Redis fue eliminado en Authentik 2025.10. A partir de esa versión (y en la 2026.x), toda la caché, tareas y sesiones usan PostgreSQL. No es necesario desplegar Redis.

### Arquitectura

```
Browser → Cloudflare → Traefik → [ForwardAuth] → Authentik
                                       ↓ OK
                                    Servicio
```

Authentik corre como tres contenedores en el stack `authentik`:

| Contenedor | Función |
| --- | --- |
| `authentik-server` | Servidor principal + outpost embebido (ForwardAuth) |
| `authentik-worker` | Procesado de tareas en background |
| `authentik-postgresql` | Base de datos (también gestiona caché y sesiones desde 2025.10) |

### Redes

| Red | Contenedores |
| --- | --- |
| `homelab_web` | `authentik-server` (y `authentik-worker`) — Traefik alcanza al server aquí |
| `authentik_internal` | Todos los contenedores del stack — red interna aislada |

> El **outpost embebido** corre dentro de `authentik-server` y no gestiona contenedores, así que Authentik **no** necesita el socket de Docker (ni `homelab_socket`).

### Variables del stack (en dockhand)

Define en el `.env` del stack `authentik` (gestionado por dockhand; modo `600` en el host):

```ini
APPDATA_DIR=/opt/homelab/appdata/authentik

# PostgreSQL
POSTGRES_DB=authentik
POSTGRES_USER=authentik
POSTGRES_PASSWORD=<password_seguro>

# Authentik
AUTHENTIK_POSTGRESQL__HOST=authentik-postgresql
AUTHENTIK_POSTGRESQL__NAME=authentik
AUTHENTIK_POSTGRESQL__USER=authentik
AUTHENTIK_POSTGRESQL__PASSWORD=<password_seguro>
AUTHENTIK_SECRET_KEY=<clave_aleatoria_60_chars>
AUTHENTIK_ERROR_REPORTING__ENABLED=false
```

Genera los valores aleatorios con:

```bash
openssl rand 60 | base64 -w 0   # para AUTHENTIK_SECRET_KEY
openssl rand 32 | base64 -w 0   # para POSTGRES_PASSWORD
```

### Configuración de Traefik

Los ficheros dinámicos viven en `stacks-templates/traefik/dynamic/` (repo) y se sirven desde `/opt/homelab/appdata/traefik/dynamic/` en el host (`sync_appdata.sh`).

**`dynamic/authentik.yaml`** — expone la UI de Authentik:

```yaml
http:
  routers:
    authentik:
      rule: "Host(`auth.example.com`)"
      entryPoints:
        - websecure
      service: authentik
      middlewares:
        - secure-headers
        - error-pages
      tls:
        certResolver: cloudflare

  services:
    authentik:
      loadBalancer:
        servers:
          - url: "http://authentik-server:9000"
```

**`dynamic/middlewares.yaml`** — añade el middleware ForwardAuth junto a los demás:

```yaml
http:
  middlewares:
    authentik-auth:
      forwardAuth:
        address: "http://authentik-server:9000/outpost.goauthentik.io/auth/traefik"
        trustForwardHeader: true
        authResponseHeaders:
          - X-authentik-username
          - X-authentik-groups
          - X-authentik-email
          - X-authentik-name
          - X-authentik-uid
          - X-authentik-jwt
          - X-authentik-meta-jwks
          - X-authentik-meta-outpost
          - X-authentik-meta-provider
          - X-authentik-meta-app
          - X-authentik-meta-version
```

Para proteger un servicio, añade el middleware `authentik-auth` a su router en `dynamic/<servicio>.yaml`:

```yaml
http:
  routers:
    <servicio>:
      rule: "Host(`<servicio>.example.com`)"
      entryPoints:
        - websecure
      middlewares:
        - authentik-auth
        - secure-headers
        - error-pages
      service: <servicio>
      tls:
        certResolver: cloudflare
```

### Setup inicial en Authentik

Una vez levantado el stack, accede a `http://<IP_LAN>:9000/if/flow/initial-setup/` para crear el usuario administrador.

#### 1. Configurar el Brand

Ve a **System → Brands** y edita el brand por defecto:

- **Domain**: `auth.example.com`
- **Default**: ✓

#### 2. Crear un Proxy Provider por cada servicio a proteger

Ve a **Applications → Providers → Create → Proxy Provider**:

| Campo | Valor |
| --- | --- |
| Name | `<servicio>-provider` |
| Authorization flow | `default-provider-authorization-implicit-consent` |
| Type | `Forward auth (single application)` |
| External host | `https://<servicio>.example.com` |
| Cookie domain | `example.com` |

#### 3. Crear una Application por cada servicio

Ve a **Applications → Applications → Create**:

| Campo | Valor |
| --- | --- |
| Name | `<Servicio>` |
| Slug | `<servicio>` |
| Provider | `<servicio>-provider` |
| Launch URL | `https://<servicio>.example.com` |

#### 4. Asignar las Applications al Outpost embebido

Ve a **Applications → Outposts**, edita `authentik Embedded Outpost` y asigna todas las aplicaciones que quieras proteger.

#### 5. Configurar el Outpost

En la configuración avanzada del outpost establece:

```yaml
authentik_host: https://auth.example.com
authentik_host_browser: https://auth.example.com
authentik_host_insecure: false
log_level: info
docker_network: null
docker_map_ports: true
refresh_interval: minutes=5
```

Guarda y reinicia el servidor para que el outpost embebido recargue la configuración:

```bash
docker restart authentik-server
```

> **Nota:** Si tras reiniciar el navegador sigue redirigiendo a `http://authentik-server:9000` en lugar del dominio público, la versión instalada no aplica el YAML de la UI al outpost embebido. En ese caso fuerza la configuración via API:
>
> ```bash
> # Obtén el token desde la BD
> docker exec authentik-postgresql psql -U authentik -d authentik \
>   -c "SELECT identifier, key FROM authentik_core_token WHERE intent='api';"
>
> # Actualiza la configuración (sustituye TOKEN y UUID por los tuyos)
> # El UUID aparece en la URL al editar el outpost
> curl -s -X PATCH \
>   "http://localhost:9000/api/v3/outposts/instances/<UUID>/" \
>   -H "Authorization: Bearer <TOKEN>" \
>   -H "Content-Type: application/json" \
>   -d '{
>     "config": {
>       "authentik_host": "https://auth.example.com",
>       "authentik_host_browser": "https://auth.example.com",
>       "authentik_host_insecure": false,
>       "log_level": "info",
>       "docker_network": null,
>       "docker_map_ports": true,
>       "refresh_interval": "minutes=5"
>     }
>   }'
>
> docker restart authentik-server
> ```

#### 6. Acceso LAN directo (fallback)

El servidor expone los puertos `9000` y `9443` directamente en la IP LAN del host para administración sin pasar por Cloudflare. Útil si el túnel no está disponible.

Para que los servicios protegidos por ForwardAuth funcionen también desde LAN sin depender de Cloudflare, configura AdGuard con registros A apuntando a la IP del host para todos los subdominios del homelab.

### Restricción de acceso por grupos (opcional)

Por defecto cualquier usuario de Authentik puede acceder a todas las aplicaciones. Para restringir:

1. Ve a **Directory → Groups → Create** y crea el grupo `homelab-admins`.
2. Añade los usuarios al grupo.
3. En cada Application ve a **Policy / Group / User Bindings** y vincula el grupo `homelab-admins`.

---

## Configuración previa en Cloudflare

Esta es la configuración que hay que dejar lista en Cloudflare **antes** de levantar los stacks `traefik` y `cloudflare`. Cubre el túnel Cloudflared, los tokens de API y el companion que sincroniza DNS con Traefik.

Valores de referencia del homelab:

- Dominio destino: `example.com`
- Zone ID: `<tu-zone-id-de-cloudflare>`
- Subdominios excluidos del companion: `internal`, `home`

### 1. Tokens de API

En **My Profile → API Tokens** crea los tokens necesarios y guárdalos en el `.env` del stack correspondiente (en dockhand; modo `600`, propietario `root`):

| Variable | Permisos mínimos | Dónde se usa |
| --- | --- | --- |
| `CF_TOKEN` | `Zone.DNS:Edit`, `Zone.Zone:Read` | stack `cloudflare` (companion) |
| `CLOUDFLARE_API_TOKEN` | `Zone.DNS:Edit`, `Zone.Zone:Read` | stack `traefik` (reto DNS-01 de Let's Encrypt) |
| `TUNNEL_TOKEN` | Lo entrega el wizard del túnel | stack `cloudflare` (cloudflared) |

`CF_TOKEN` y `CLOUDFLARE_API_TOKEN` pueden ser el mismo token si los permisos coinciden, pero conviene separarlos para poder revocarlos por servicio.

### 2. Crear el túnel

1. Entra en **Zero Trust → Networks → Tunnels → Create a tunnel**.
2. Elige conector **Cloudflared** y copia el `TUNNEL_TOKEN` que aparece (lo necesitas en el `.env` del stack `cloudflare`).
3. En **Public Hostnames**, añade una entrada con:
   - **Subdomain**: `*` (comodín — todos los subdominios)
   - **Service**: `HTTPS` → URL `traefik:80`
4. Despliega **Additional application settings → TLS** y configura:
   - **Origin Server Name**: `*.example.com`
   - **No TLS Verify**: ON

Con esto, Cloudflare entrega cualquier `*.example.com` al contenedor `traefik` por la red interna.

### 3. CNAMEs automáticos (cloudflare-companion)

El servicio `cloudflare-companion` lee la configuración de Traefik (labels y ficheros dinámicos) y crea automáticamente los CNAMEs que apuntan a `example.com`. No hay que mantener registros DNS a mano por cada servicio nuevo.

Los subdominios `internal` y `home` están **excluidos** por configuración para reservarlos a uso local.

### 4. Verificación

Tras arrancar el stack `cloudflare`, revisa los logs de `cloudflare-tunnels` y `cloudflare-companion` desde dockhand (o por `docker compose logs` sobre la receta en `/opt/homelab/stacks/...`). Comprueba que el túnel sale como `Registered` y que el companion reporta `Created CNAME` por cada router dado de alta en Traefik.

---

## Operación habitual

- **Servicios gestionados por dockhand:** opéralos desde la UI (deploy, logs, restart, update). El runtime vive en `/opt/homelab/stacks/<stack>/` (hawser) y la copia central en `/opt/homelab/appdata/dockhand/stacks/{env}/{stack}/`.
- **Bootstrap (`hawser`, `dockhand`):** por terminal.

  ```bash
  cd /opt/homelab/docker/<hawser|dockhand>
  docker compose up -d            # levantar
  docker compose ps               # estado
  docker compose logs -f          # logs
  docker compose pull && docker compose up -d   # actualizar
  docker compose down             # parar
  ```

- **Rescate sin UI:** SSH al host y `docker compose` directamente sobre la receta en `/opt/homelab/stacks/...`.
- **Cambios de config versionada** (traefik.yaml, dynamic/, unbound.conf…): edítalos en el repo (`stacks-templates/<svc>/`) y reejecuta `sudo ./scripts/sync_appdata.sh` para llevarlos a `appdata`.
- **Dominio o email ACME:** edita `/opt/homelab/docker/.env` (`FQDN`, `ACME_EMAIL`) y reejecuta `sudo ./scripts/sync_appdata.sh`.

Logs de Traefik (acceso y servicio) en `/opt/homelab/appdata/traefik/logs/`.

---

## Añadir un servicio nuevo

1. Crea la receta en `stacks-templates/<servicio>/docker-compose.yaml`. Usa `container_name`, `hostname`, `restart: unless-stopped`.
2. `env_file`: el común del host (`/opt/homelab/docker/.env`) + el `.env` del stack (relativo). Define `APPDATA_DIR=/opt/homelab/appdata/<servicio>` en el `.env` del stack.
3. Referencia los volúmenes vía `${APPDATA_DIR}/...` (ruta absoluta) — nunca hardcodees la ruta.
4. Conéctate a las redes externas existentes; **no** declares redes nuevas inline. `homelab_web` si se expone por Traefik, `homelab_socket` solo si necesitas `socket-proxy-ro`, `homelab_dns` solo para plano DNS.
5. Si lleva config en fichero, ponla en `stacks-templates/<servicio>/` y se copiará a `appdata` con `sync_appdata.sh`.
6. Para exponerlo vía Traefik:
   - Copia `stacks-templates/traefik/dynamic/_router-template.yaml` a `stacks-templates/traefik/dynamic/<servicio>.yaml`.
   - Edítalo apuntando al host interno (`http://<container>:<port>`).
   - Aplica middlewares `secure-headers` y `error-pages`.
   - **No** uses `labels` de Traefik en el compose (el provider está con `exposedByDefault: false`).
7. Sincroniza la config y crea el stack en dockhand:

   ```bash
   sudo ./scripts/sync_appdata.sh   # lleva la config a appdata
   ```

   Luego, en la UI de dockhand, crea el stack a partir de la receta y despliégalo en el environment del host.

---

## Seguridad y permisos

- **umask 027** para el usuario (`fix_unmask.sh`): nuevos ficheros `640`, nuevas carpetas `750`.
- **`fix_permissions.sh`** refuerza, sobre todo `/opt/homelab` (usa `-xdev`: no cruza a montajes externos como un NAS):
  - Propietario detectado (`${SUDO_UID:-$(id -u)}:${SUDO_GID:-...}`) recursivo.
  - Carpetas `750`, ficheros `640`.
  - `*.sh` → `750`, `*.env` → `600`.
  - Carpetas `secret(s)/` → `700`.
  - Ficheros `*.pem`, `*.key`, `id_rsa`, `id_ed25519` → `600`.
  - `.git/` se ignora.
- IPv6 deshabilitado a nivel kernel (`/etc/sysctl.d/99-homelab-disable-ipv6.conf`).
- **Firewall del host (UFW)**: lo activa `scripts/enable_firewall.sh` (lo lanza `init.sh`). Política `default deny incoming` + `default allow outgoing`, con tres reglas:
  - `22/tcp` — **SSH (imprescindible también para acceso local en LAN)**. Sin esta regla pierdes la sesión SSH al hacer `ufw enable`, por eso el script la añade **antes** de habilitar UFW.
  - `80/tcp`, `443/tcp` — Traefik (HTTP/HTTPS).
  - Los puertos publicados por contenedores Docker (p.ej. `8085` de dockhand, `53`/`8054` de AdGuard, `9000` de Authentik) **no** los filtra UFW: Docker inyecta sus propias reglas en `iptables` antes del `INPUT` de UFW. Para bloquearlos no se publican al host (o se publican en `127.0.0.1`).
- Acceso al socket Docker: lectura vía `socket-proxy-ro`; escritura solo por `hawser` (con token), único contenedor con el socket crudo.
- Cabeceras HTTPS endurecidas vía middleware `secure-headers` de Traefik (HSTS, CSP, frame-deny, etc.).

Re-ejecuta `sudo ./scripts/fix_permissions.sh` tras cualquier copia manual dentro de `/opt/homelab`.

---

## Tareas programadas (cron)

Las instala el bootstrap, son idempotentes (no se duplican):

| Fichero | Frecuencia | Función |
| --- | --- | --- |
| `/etc/cron.d/homelab-autoupdate` | Diaria 03:00 | `apt-get upgrade` desatendido + reinicio **solo si** `/var/run/reboot-required` → `/var/log/homelab-autoupdate.log` |
| `/etc/cron.d/homelab-unbound-update` | Mensual día 1, 04:00 | `docker pull` + recreate del stack Unbound (refresca raíces baked + parches) → `/var/log/homelab-unbound.log` |
