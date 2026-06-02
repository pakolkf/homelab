# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Propósito del repo

Homelab basado en Docker Compose sobre un host Linux (Ubuntu/Debian). Dos directorios de primer nivel:

- `scripts/` — scripts de bootstrap del host (se ejecutan como root sobre la máquina destino).
- `docker/` — una carpeta por servicio, cada una con su propio `docker-compose.yaml`.

Este repositorio es la **fuente de verdad**, pero todo está diseñado para vivir en `/opt/homelab/` del host. El despliegue sigue el modelo **dockhand-first** (ver sección siguiente): solo `hawser` y `dockhand` se copian a `/opt/homelab/docker/` y se levantan por terminal; el resto de servicios los gestiona dockhand.

## Modelo de despliegue (dockhand-first)

**Solo `hawser` y `dockhand` se instalan por terminal** (`docker compose up` tras el bootstrap del host). El resto de servicios (traefik, dns, authentik, homarr, vaultwarden…) se instalan y configuran **desde la UI de dockhand**, que los gestiona como stacks.

Tres árboles en el host:

- `/opt/homelab/docker/` — **bootstrap**: compose + `.env` de `hawser` y `dockhand`, y el `.env` global del host.
- `/opt/homelab/stacks/<stack>/` — **runtime de hawser** de este host (su `STACKS_DIR`; lo que hawser ejecuta, plano por host).
- `/opt/homelab/appdata/dockhand/stacks/{env}/{stack}/` — **copia central** de dockhand (todos los environments; estructura impuesta `{DATA_DIR}/stacks/{env}/{stack}/compose.yaml`, rígida). dockhand **NO** monta este dir sobre `/opt/homelab/stacks` (colisionaría con la copia plana de hawser). Los stacks de Git: `/opt/homelab/appdata/dockhand/git-repos/{env}/{stack}/` (los importados se quedan en su sitio).
- `/opt/homelab/appdata/<servicio>/` — **config + datos** de cada servicio (todo lo que el contenedor monta salvo la receta).

### Reglas para los stacks gestionados por dockhand

- **Rutas de volúmenes absolutas** (`/opt/homelab/appdata/<svc>/…`): hawser ejecuta el compose en el host destino; las rutas relativas no valen en hosts remotos.
- **Doble `env_file`**:
  - `/opt/homelab/docker/.env` — `PUID/PGID/TZ` y rutas. **Es local a cada host** (mismo path, contenido propio), autodetectado por `create_estructure.sh` (`${SUDO_UID:-$(id -u)}`). hawser lo monta `:ro` para resolverlo; como ejecuta en el host destino, cada host inyecta sus propios uids (clave para hosts remotos con uid distinto).
  - `.env` del stack — config/secretos de la app; lo gestiona dockhand en el dir del stack.
- La config versionada (p.ej. `traefik.yaml`, `dynamic/`, `unbound.conf`) vive en `appdata/<svc>/`; dockhand solo escribe el `compose`, esos ficheros los colocas tú (file-manager de dockhand, git o a mano).

El flujo legacy de "copiar `docker/<svc>/` al host y `docker compose up`" (secciones siguientes) aplica ahora **solo** a `hawser`/`dockhand`.

## Bootstrap del host

Punto de entrada único que encadena todos los scripts de preparación en orden:

```bash
sudo ./scripts/init.sh
```

`init.sh` ejecuta (por orden): `auto_update.sh`, `set_ip.sh`, `update_unbound_stack.sh`, `disable_ipv6.sh`, `disable_dns.sh`, `fix_unmask.sh`, `create_estructure.sh`, `fix_overcommit.sh`, `sync_appdata.sh`, `fix_permissions.sh`, `install_docker.sh`, `create_docker_network.sh`.

El orden importa — `create_estructure.sh` debe ejecutarse antes que cualquier `fix_*` que toque `/opt/homelab`, e `install_docker.sh` debe preceder a `create_docker_network.sh`.

Los scripts individuales son reentrantes (idempotentes): cada uno comprueba si su configuración ya existe (ficheros cron, `.env` existente, redes ya creadas) y sale sin tocar nada.

## Levantar un stack

Cada stack se lanza desde dentro de `/opt/homelab/docker/<servicio>/` para que `${STACK_DIR}` resuelva correctamente (lo aporta el `.env` por stack, ver más abajo).

```bash
cd /opt/homelab/docker/<servicio>
docker compose up -d
docker compose logs -f
docker compose down
```

Orden de arranque del homelab completo: `socket-proxy` → `unbound` → `adguard` → `traefik` (+ `error-pages`) → resto.

## Arquitectura

### Tres redes Docker externas

Creadas por `scripts/create_docker_network.sh`. Todos los stacks se conectan a una o varias — ninguna se define inline en los compose.

- `homelab_web` — todo lo que se expone vía Traefik (HTTP/HTTPS).
- `homelab_socket` — plano del socket de Docker: lectura vía `socket-proxy-ro`; la única excepción con socket crudo (rw) es `hawser`, el agente de escritura de dockhand.
- `homelab_dns` — plano DNS (unbound recursivo + adguard).

### DNS en capas

`adguard` (puerto 53, filtrado) → `unbound` (puerto 5335 dentro de `homelab_dns`, resolutor recursivo con DNSSEC). Las raíces (`root.hints` + ancla DNSSEC) las trae *baked* la imagen `klutchell/unbound` y unbound mantiene el ancla en runtime (`auto-trust-anchor-file`/RFC5011); **no** se montan ni se declaran en `unbound.conf` (duplicarlas da "presented twice"). Para refrescarlas, `update_unbound_stack.sh` instala un cron mensual (`/etc/cron.d/homelab-unbound-update`) que hace `docker pull` + recreate del stack.

`disable_dns.sh` desactiva el stub listener de `systemd-resolved` para liberar el puerto 53 para AdGuard, y enlaza `/etc/resolv.conf` a `/run/systemd/resolve/resolv.conf`.

### Patrón Traefik + socket-proxy

Traefik **no** monta `/var/run/docker.sock`. Habla con `socket-proxy-ro` (sólo lectura, expone únicamente PING/VERSION/EVENTS/CONTAINERS/NETWORKS) sobre `tcp://socket-proxy-ro:2375` en `homelab_socket`. Es el único proxy del socket: lo consumen en lectura Traefik, dozzle, beszel, cloudflare-companion y homarr.

Los servicios que necesitan **escritura** no usan un socket-proxy rw — `dockhand` gestiona Docker a través de su agente `hawser` (token, `http://hawser:2376` en `homelab_socket`), que es el único contenedor que monta el socket crudo (rw) y además monta su `STACKS_DIR` (`/opt/homelab/stacks`).

División de la configuración Traefik:
- `traefik/traefik.yaml` — configuración estática (entrypoints, providers, resolvers ACME).
- `traefik/dynamic/*.yaml` — rutas y middlewares del file-provider. Usa `_router-template.yaml` como punto de partida al exponer un nuevo servicio.
- Dos resolvers ACME: `letsencrypt-staging` (actualmente el por defecto en `entryPoints.websecure`) y `letsencrypt-production`. Para pasar a producción se edita `traefik.yaml` — no comitear certs emitidos.
- Reto DNS-01 contra Cloudflare, por lo que el token de API de Cloudflare va en `docker/traefik/.env` (no en este repo).

### Convención de env-files y variables

**Clave:** `env_file:` solo **inyecta** variables al contenedor; **no** sirven para interpolar `${...}` en el compose. La interpolación toma valores del `.env` del **directorio del proyecto** (el del propio stack) o del shell — **nunca** del `.env` global. Por eso:

- Variables que aparecen en `volumes`/`ports`/`image` → deben estar en el `.env` del stack (`${APPDATA_DIR}`, `${POSTGRES_DB}`, `${TS_HOSTNAME}`…), o ser **ruta fija** (`hawser`/`dockhand` hardcodean `/opt/homelab/stacks` y `/opt/homelab/appdata/dockhand`).
- Variables que solo necesita el proceso de dentro (`PUID/PGID/TZ`, tokens, secretos) → vía `env_file:`, y ahí el `.env` global vale.

`docker/.env` (global, versionado, no sensible): `PUID/PGID/TZ`, `FQDN`, `ACME_EMAIL`, y rutas base (`HOMELAB_BASE/STACKS_BASE/APPDATA`).
- `PUID/PGID/TZ` se inyectan a los contenedores; **se autodetectan por host** (`${SUDO_UID:-$(id -u)}`) — el `.env` global es local a cada host.
- `FQDN/ACME_EMAIL` los **renderiza `sync_appdata.sh`** en los configs (no se interpolan en compose).
- Las rutas base son **informativas / las usa `create_estructure.sh`** para crear dirs; los compose ya no las interpolan.

`.env` por stack (`600`, root, **no** en el repo — los gestiona dockhand o se crean a mano): `APPDATA_DIR=/opt/homelab/appdata/<svc>` + secretos de la app. Excepción versionada: `stacks-templates/socket-proxy/.env` (solo-lectura, sin secretos).

### Modelo de permisos

`fix_unmask.sh` fija `umask 027` para el usuario del host (ficheros nuevos 640, carpetas 750). `fix_permissions.sh` luego refuerza, en todo `/opt/homelab`:

- Todo propiedad de `1000:1000`.
- Carpetas `750`, ficheros `640`, `*.sh` `750`, `*.env` `600`, carpetas `secret(s)/` `700`, ficheros `*.pem` / `*.key` / `id_rsa` / `id_ed25519` `600`.
- Las carpetas `.git` se ignoran (`-prune`).

Reejecutar `sudo ./scripts/fix_permissions.sh` tras cualquier copia manual dentro de `/opt/homelab`.

### Particularidades

- `fix_overcommit.sh` fija `vm.overcommit_memory=1` (`/etc/sysctl.d/99-homarr-redis.conf`) — requerido por el Redis interno de Homarr.
- `auto_update.sh` instala un cron diario en `/etc/cron.d/homelab-autoupdate` que hace `apt-get upgrade` a las 03:00, log en `/var/log/homelab-autoupdate.log`.
- `tailscale` corre con `network_mode: host` y NO se une a las redes homelab — saltárselo si se buscan errores de descubrimiento entre contenedores.

## Convenciones para añadir un stack nuevo

1. Crear `docker/<servicio>/docker-compose.yaml`. Usar `container_name`, `hostname`, `restart: unless-stopped`.
2. Cargar los dos `env_file` (global + por-stack) como arriba.
3. Referenciar rutas vía `${STACK_DIR}` — nunca hardcodear `/opt/homelab/docker/<servicio>`.
4. Conectarse a redes externas existentes; **no** declarar nuevas inline. `homelab_web` para servicios expuestos por Traefik, `homelab_socket` sólo si se necesita socket-proxy, `homelab_dns` sólo para plano DNS.
5. Para exponer vía Traefik, copiar `docker/traefik/dynamic/_router-template.yaml` a `docker/traefik/dynamic/<servicio>.yaml` y editar — rutas en file-provider, **no** labels en el compose (`exposedByDefault: false` está activo).
6. Middlewares por defecto: `secure-headers, error-pages`.
7. Después de copiar al host: `sudo ./scripts/fix_permissions.sh`.
