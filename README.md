# homelab

Homelab autoalojado basado en **Docker Compose** sobre un host Linux (Ubuntu/Debian), con bootstrap automatizado del sistema, DNS recursivo propio, reverse proxy con TLS automático y un catálogo de servicios habituales (dashboard, gestor de ficheros, backups, monitorización, VPN…).

Todo el stack está pensado para vivir en `/opt/homelab/` del host. Este repositorio es la **fuente de verdad** que se sincroniza a esa ruta.

---

## Tabla de contenidos

- [Requisitos](#requisitos)
- [Estructura del repositorio](#estructura-del-repositorio)
- [Instalación rápida](#instalación-rápida)
- [Arquitectura](#arquitectura)
- [Servicios incluidos](#servicios-incluidos)
- [Configuración previa en Cloudflare](#configuración-previa-en-cloudflare)
- [Operación habitual](#operación-habitual)
- [Añadir un servicio nuevo](#añadir-un-servicio-nuevo)
- [Seguridad y permisos](#seguridad-y-permisos)
- [Tareas programadas (cron)](#tareas-programadas-cron)

---

## Requisitos

- Host con **Ubuntu / Debian** (los scripts usan `apt-get` y `systemd-resolved`).
- Acceso `root` (vía `sudo`).
- Dominio propio gestionado en **Cloudflare** (necesario para el reto DNS-01 de Let's Encrypt). El dominio por defecto en la config es `example.com` — cámbialo en `docker/.env` y en `docker/traefik/traefik.yml`.
- Conectividad saliente a los registros de imagen y a Let's Encrypt.

Docker y Docker Compose **no** son requisitos previos: los instala `scripts/install_docker.sh`.

---

## Estructura del repositorio

```
.
├── docker/                      Stacks Docker Compose (uno por servicio)
│   ├── .env                     Variables globales no sensibles
│   ├── adguard/                 DNS con filtrado
│   ├── beszel/                  Monitorización ligera
│   ├── cloudflare/              Cloudflare Tunnel + companion para Traefik
│   ├── dockhand/                Gestión visual de stacks
│   ├── dozzle/                  Logs de contenedores en vivo
│   ├── duplicati/               Backups
│   ├── filebrowser/             Explorador de ficheros web
│   ├── homarr/                  Dashboard principal
│   ├── nutify/                  Notificaciones / monitor UPS
│   ├── socket-proxy/            Proxy lectura + lectura-escritura al socket
│   ├── tailscale/               VPN mesh (network_mode: host)
│   ├── traefik/                 Reverse proxy + TLS (Let's Encrypt)
│   ├── unbound/                 DNS recursivo (DNSSEC)
│   ├── uptime-kuma/             Monitorización de uptime
│   ├── vaultwarden/             Gestor de contraseñas (Bitwarden compat.)
│   └── wgdashboard/             Panel WireGuard
└── scripts/                     Scripts de bootstrap del host
    ├── init.sh                  Orquestador (lanza todo lo demás en orden)
    ├── auto_update.sh           Cron diario apt-get upgrade
    ├── update_unbound_roots.sh  Cron mensual root.hints + root.key
    ├── disable_ipv6.sh          Desactiva IPv6 (sysctl)
    ├── disable_dns.sh           Desactiva stub de systemd-resolved
    ├── fix_unmask.sh            umask 027 para el usuario
    ├── create_estructure.sh     Crea /opt/homelab y .env global
    ├── fix_homarr.sh            Ajustes específicos de Homarr (sysctl)
    ├── fix_permissions.sh       Refuerza propietario y modos
    ├── install_docker.sh        Instala Docker Engine + Compose plugin
    └── create_docker_network.sh Crea las 3 redes externas del homelab
```

---

## Instalación rápida

1. Clona o copia este repositorio en el host (ej. `/root/homelab`).

2. Ejecuta el bootstrap completo (todo en orden y de forma idempotente):

   ```bash
   sudo ./scripts/init.sh
   ```

   Esto deja el sistema preparado: actualizado, sin IPv6, con DNS del host bien configurado, con `/opt/homelab/` creado, con Docker instalado y con las redes `homelab_web`, `homelab_socket` y `homelab_dns` ya creadas.

3. Sincroniza el directorio `docker/` de este repo a `/opt/homelab/docker/`:

   ```bash
   sudo rsync -a --delete ./docker/ /opt/homelab/docker/
   sudo ./scripts/fix_permissions.sh
   ```

4. Crea los ficheros `.env` por stack (cada carpeta de `docker/<servicio>/` necesita el suyo). Como mínimo deben definir:

   ```ini
   STACK_DIR=/opt/homelab/docker/<servicio>
   ```

   Más cualquier secreto propio del servicio (token de Cloudflare para Traefik, credencial de Tailscale, etc.). Estos `.env` son **600**, propiedad de root, y no deben subirse a git.

5. Levanta los stacks en orden:

   ```bash
   cd /opt/homelab/docker/socket-proxy && docker compose up -d
   cd /opt/homelab/docker/unbound      && docker compose up -d
   cd /opt/homelab/docker/adguard      && docker compose up -d
   cd /opt/homelab/docker/traefik      && docker compose up -d
   # …luego el resto en cualquier orden
   ```

---

## Arquitectura

### Tres redes Docker externas

Todas se crean en `scripts/create_docker_network.sh` y los compose se conectan a ellas como `external: true`:

| Red | Para qué sirve |
| --- | --- |
| `homelab_web` | Tráfico HTTP/HTTPS que pasa por Traefik. |
| `homelab_socket` | Acceso al socket de Docker, siempre vía `socket-proxy`. |
| `homelab_dns` | Plano DNS interno (AdGuard ↔ Unbound). |

### Cadena DNS

```
clientes → AdGuard (53, filtrado) → Unbound (5335, recursivo + DNSSEC) → raíz
```

`scripts/disable_dns.sh` libera el puerto 53 desactivando el stub listener de `systemd-resolved`. Un cron mensual (`scripts/update_unbound_roots.sh`) refresca `root.hints` y `root.key` y reinicia Unbound.

### Traefik sin acceso directo al socket

Traefik nunca monta `/var/run/docker.sock`. Habla con `socket-proxy-ro` (read-only) por `tcp://socket-proxy-ro:2375`. Existe además un `socket-proxy` (read-write) para los pocos servicios que sí necesitan escritura.

- Configuración estática: `docker/traefik/traefik.yml` (entrypoints, providers, ACME).
- Configuración dinámica (rutas/middlewares): `docker/traefik/dynamic/*.yml` (file-provider).
- TLS automático con **Let's Encrypt**, reto **DNS-01 contra Cloudflare**.
- Dos resolvers: `letsencrypt-staging` (por defecto) y `letsencrypt-production`. Cambia el resolver activo en `entryPoints.websecure` cuando todo funcione en staging.
- Páginas de error servidas por `tarampampam/error-pages` (router catch-all `error-pages-fallback`).
- Cabeceras seguras por defecto vía middleware `secure-headers` (HSTS, X-Frame-Options, CSP, etc.).

### Convención de ficheros `.env`

Cada compose carga **dos** ficheros:

```yaml
env_file:
  - /opt/homelab/docker/.env              # global (no sensible)
  - /opt/homelab/docker/<servicio>/.env   # por-stack (secretos + STACK_DIR)
```

El `docker/.env` versionado en este repo contiene únicamente valores por defecto no sensibles:

```ini
PUID=1000
PGID=1000
TZ=Europe/Madrid
FQDN=example.com
HOMELAB_BASE=/opt/homelab
```

Los `.env` por servicio se crean en el host, son `600` propiedad de root, y deben definir `STACK_DIR`.

---

## Servicios incluidos

| Stack | Imagen | Puerto host | Función |
| --- | --- | --- | --- |
| traefik | `traefik:latest` | 80, 443, 8080 | Reverse proxy + TLS automático |
| error-pages | `tarampampam/error-pages` | 8090 | Páginas de error personalizadas |
| socket-proxy | `lscr.io/linuxserver/socket-proxy` | 2375 (rw), 2376 (ro) | Acceso controlado al socket Docker |
| unbound | `mvance/unbound` | — (interno 5335) | DNS recursivo con DNSSEC |
| adguard | `adguard/adguardhome` | 53, 8054 | DNS con filtrado de anuncios |
| homarr | `ghcr.io/homarr-labs/homarr` | 7575 | Dashboard del homelab |
| dockhand | `fnsys/dockhand` | 8085 | Gestor visual de stacks |
| dozzle | `amir20/dozzle` | 8086 | Logs en vivo de contenedores |
| beszel | `henrygd/beszel` | 8091 | Métricas de servidores |
| uptime-kuma | `louislam/uptime-kuma` | 3013 | Monitor de uptime |
| nutify | `dartsteven/nutify` | 5050 | Notificaciones / UPS |
| filebrowser | `filebrowser/filebrowser` | 8088 | Navegador web de ficheros |
| duplicati | `lscr.io/linuxserver/duplicati` | 8200 | Backups |
| vaultwarden | `vaultwarden/server` | 8222 | Gestor de contraseñas |
| wgdashboard | `ghcr.io/wgdashboard/wgdashboard` | 10086, 51820/udp | Panel WireGuard |
| tailscale | `tailscale/tailscale` | host network | VPN mesh |
| cloudflare-tunnels | `cloudflare/cloudflared` | — | Túnel Cloudflare |
| cloudflare-companion | `tiredofit/docker-traefik-cloudflare-companion` | — | Sincroniza routers de Traefik con DNS de Cloudflare |

---

## Configuración previa en Cloudflare

Esta es la configuración que hay que dejar lista en Cloudflare **antes** de levantar los stacks `traefik` y `cloudflare`. Cubre el túnel Cloudflared, los tokens de API y el companion que sincroniza DNS con Traefik.

Valores de referencia del homelab:

- Dominio destino: `example.com`
- Zone ID: `your-cloudflare-zone-id`
- Subdominios excluidos del companion: `internal`, `home`

### 1. Tokens de API

En **My Profile → API Tokens** crea los tokens necesarios y guárdalos en los `.env` correspondientes (modo `600`, propietario `root`):

| Variable | Permisos mínimos | Dónde se usa |
| --- | --- | --- |
| `CF_TOKEN` | `Zone.DNS:Edit`, `Zone.Zone:Read` | `docker/cloudflare/.env` (companion) |
| `CLOUDFLARE_API_TOKEN` | `Zone.DNS:Edit`, `Zone.Zone:Read` | `docker/traefik/.env` (reto DNS-01 de Let's Encrypt) |
| `TUNNEL_TOKEN` | Lo entrega el wizard del túnel | `docker/cloudflare/.env` (cloudflared) |

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

El servicio `cloudflare-companion` lee la configuración de Traefik (tanto labels como ficheros dinámicos en `docker/traefik/dynamic/`) y crea automáticamente los CNAMEs que apuntan a `example.com`. No hay que mantener registros DNS a mano por cada servicio nuevo.

Los subdominios `internal` y `home` están **excluidos** por configuración para reservarlos a uso local.

### 4. Verificación

Tras arrancar el stack `cloudflare`:

```bash
cd /opt/homelab/docker/cloudflare
docker compose logs -f cloudflare-tunnels cloudflare-companion
```

Comprueba que `cloudflare-tunnels` muestra el túnel `Registered` y que `cloudflare-companion` reporta `Created CNAME` por cada router que tengas dado de alta en Traefik.

---

## Operación habitual

Trabaja siempre desde el directorio del stack (para que `${STACK_DIR}` se resuelva):

```bash
cd /opt/homelab/docker/<servicio>

docker compose up -d            # levantar
docker compose ps               # estado
docker compose logs -f          # logs en vivo
docker compose pull && docker compose up -d   # actualizar
docker compose down             # parar
```

Logs de Traefik (acceso y servicio) en `docker/traefik/logs/`.

---

## Añadir un servicio nuevo

1. Crea `docker/<servicio>/docker-compose.yml`. Usa `container_name`, `hostname`, `restart: unless-stopped`.
2. Carga los dos `env_file` (global + por-stack).
3. Referencia rutas vía `${STACK_DIR}` — nunca hardcodees `/opt/homelab/docker/<servicio>`.
4. Conéctate a las redes externas existentes; **no** declares redes nuevas inline. `homelab_web` si se expone por Traefik, `homelab_socket` sólo si necesitas socket-proxy, `homelab_dns` sólo para plano DNS.
5. Para exponerlo vía Traefik:
   - Copia `docker/traefik/dynamic/_router-template.yml` a `docker/traefik/dynamic/<servicio>.yml`.
   - Edítalo apuntando al host interno (`http://<container>:<port>`).
   - Aplica middlewares `secure-headers` y `error-pages`.
   - **No** uses `labels` de Traefik en el compose (el provider está con `exposedByDefault: false`).
6. Sincroniza al host y ejecuta:

   ```bash
   sudo rsync -a ./docker/<servicio>/ /opt/homelab/docker/<servicio>/
   sudo ./scripts/fix_permissions.sh
   cd /opt/homelab/docker/<servicio> && docker compose up -d
   ```

---

## Seguridad y permisos

- **umask 027** para el usuario (`fix_unmask.sh`): nuevos ficheros `640`, nuevas carpetas `750`.
- **`fix_permissions.sh`** refuerza, sobre todo `/opt/homelab`:
  - Propietario `1000:1000` recursivo.
  - Carpetas `750`, ficheros `640`.
  - `*.sh` → `750`.
  - `*.env` → `600`.
  - Carpetas `secret(s)/` → `700`.
  - Ficheros `*.pem`, `*.key`, `id_rsa`, `id_ed25519` → `600`.
  - `.git/` se ignora.
- IPv6 deshabilitado a nivel kernel (`/etc/sysctl.d/99-homelab-disable-ipv6.conf`).
- Acceso al socket Docker **siempre** a través de `socket-proxy` (variante read-only por defecto).
- Cabeceras HTTPS endurecidas vía middleware `secure-headers` de Traefik (HSTS, CSP, frame-deny, etc.).

Re-ejecuta `sudo ./scripts/fix_permissions.sh` tras cualquier copia manual dentro de `/opt/homelab`.

---

## Tareas programadas (cron)

Las instala el bootstrap, son idempotentes (no se duplican):

| Fichero | Frecuencia | Función |
| --- | --- | --- |
| `/etc/cron.d/homelab-autoupdate` | Diaria 03:00 | `apt-get upgrade` desatendido → `/var/log/homelab-autoupdate.log` |
| `/etc/cron.d/homelab-unbound-roots` | Mensual día 1, 04:00 | Refresca `root.hints` + `root.key` de Unbound y reinicia el contenedor → `/var/log/homelab-unbound.log` |
