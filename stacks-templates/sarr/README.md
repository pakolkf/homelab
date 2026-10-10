# sarr

Gestores de biblioteca: **Radarr** (películas) · **Sonarr** (series) · **Bazarr**
(subtítulos) · **Unpackerr** (descompresión) · **Profilarr** (+ `profilarr-parser`).
Todos en `homelab_web`; montan `MEDIA_DIR` en `/data_arr` (descargas y biblioteca
en el **mismo** punto de montaje → hardlinks/movimientos atómicos, sin copiar).

---

## Profilarr — perfiles comunes Radarr + Sonarr (castellano + VO, ≥1080p)

Profilarr (v2) es la **fuente de verdad** de los perfiles de calidad, custom
formats (CF), tamaños, naming y delay profiles. Los empuja (sync) a Radarr y
Sonarr, así ambos usan **exactamente** la misma configuración.

> ⚠️ A partir de aquí **no edites perfiles ni CF en Radarr/Sonarr a mano**: el
> siguiente sync los pisa. Todo se cambia en Profilarr.
> Antes del primer sync, haz backup de Radarr y Sonarr (*System → Backup*).

### Objetivo

| Requisito | Cómo se consigue |
| --- | --- |
| Mínimo 1080p | El perfil solo habilita calidades 1080p (sin SD/720p/CAM/TS) |
| Audio **castellano** obligatorio | CF `ES - Castellano` (+1000) |
| Audio **VO** obligatorio | CF `VO - Original/Dual` (+1000) |
| "Obligatorio" | *Minimum Custom Format Score* = **2000** → hacen falta ambos |
| Evitar latino / VOSE | CF con **-10000** (descarte inmediato) |
| Tamaño razonable | *Quality Definitions* (MB/min) comunes |

Para una película **española** (VO = castellano), Radarr/Sonarr evalúan `Original`
contra el idioma original de TMDB/TVDB, así que un release solo en castellano
cumple ambos CF y llega a 2000. Para una película en inglés hace falta dual.

### 0. Preparación

1. En Radarr y Sonarr copia la **API key** (*Settings → General*).
2. En **Prowlarr**, para cada indexer español (DonTorrent, MejorTorrent, etc.),
   revisa si su configuración tiene la opción *Multi Languages* /
   "añadir idioma al título" y márcala con **Spanish + English**. Así los
   releases `MULTi` se interpretan con castellano y la detección de idioma mejora.
3. Asegúrate de que Prowlarr sincroniza esos indexers a Radarr **y** Sonarr.

### 1. Conectar las instancias (*Arr Instances*)

| Nombre | Tipo | URL | API key |
| --- | --- | --- | --- |
| `radarr` | Radarr | `http://radarr:7878` | la de Radarr |
| `sonarr` | Sonarr | `http://sonarr:8989` | la de Sonarr |

Las URLs son internas (red `homelab_web`), no las de Traefik.

### 2. Vincular una base de datos

*Databases → Link* → `https://github.com/Dictionarry-Hub/database`.

No usaremos sus perfiles (están pensados para trackers privados en inglés y
descartarían casi todo lo que viene de trackers españoles), pero **reutilizamos
sus CF genéricos** (3D, Upscaled, Repack…). Todo lo que creemos encima va a la
capa *user* y **sobrevive** a las actualizaciones de la base.

> **No borres nada de lo que trae la base** (perfiles, CF, regex). Solo llega a
> Radarr/Sonarr lo que marques en el *Sync* (paso 9): los perfiles elegidos y
> los CF que esos perfiles usan. El resto se queda dentro de Profilarr sin
> efecto. Borrarlo genera cientos de cambios locales que chocan con cada
> actualización de la base y te quita CF que sí usamos (3D, Repack…).

### 3. Expresiones regulares (*Regular Expressions*)

Crea estas cinco (son case-insensitive en Radarr/Sonarr). En la tabla `\|` es solo
el escape de Markdown: al copiarlas escribe `|` a secas.

| Nombre | Patrón |
| --- | --- |
| `ES Castellano` | `\b(castellano\|espa[ñn]ol\|spanish\|esp\|spa)\b` |
| `ES Castellano explícito` | `\b(castellano\|espa[ñn]a)\b` |
| `ES Latino` | `\b(latino\|latam\|latinoam[eé]rica(no)?)\b` |
| `VO Dual` | `\b(dual\|multi\|v\.?o\.?\|ingl[eé]s\|english\|eng\|ES[ ._-]EN)\b` |
| `VOSE` | `\bv\.?o\.?s\.?e\b` |

### 4. Custom Formats

En cada CF las condiciones **no marcadas como *required*** se combinan con **O**;
las *required* con **Y**.

| CF | Condiciones | Puntuación |
| --- | --- | --- |
| `ES - Castellano` | *Language* = Spanish **o** *Release Title* = `ES Castellano` | **+1000** |
| `VO - Original/Dual` | *Language* = Original **o** *Release Title* = `VO Dual` | **+1000** |
| `ES - Solo latino` | *(required)* *Release Title* = `ES Latino` **y** *(required, negate)* *Release Title* = `ES Castellano explícito` | **-10000** |
| `VOSE` | *Release Title* = `VOSE` | **-10000** |

Añade a cada CF unos **tests** (pestaña *Testing*, usa el parser) con títulos
reales de tus indexers. Ejemplos:

| Título | Debe sumar |
| --- | --- |
| `Dune Parte Dos (2024) [BluRay 1080p][DTS 5.1 Castellano DTS-HD 7.1 Ingles+Subs]` | 2000 ✅ |
| `Dune.Part.Two.2024.1080p.MULTi.SPANiSH.ENGLiSH.WEB-DL.DDP5.1.x264` | 2000 ✅ |
| `Dune Parte Dos (2024) [1080p][Castellano AC3 5.1]` | 1000 ❌ (sin VO) |
| `Dune Part Two (2024) 1080p WEB-DL Latino` | -10000 ❌ |
| `Dune.Part.Two.2024.1080p.BluRay.x264-GROUP` | ≤1000 ❌ (sin castellano) |
| `El 47 (2024) [1080p][Castellano]` (película española) | 2000 ✅ |

### 5. Perfil de calidad `ES+VO 1080p`

*Quality Profiles → New*. Mismo perfil para Radarr y Sonarr (puntuaciones con
`arr_type = all`).

**Calidades** (de mejor a peor, el resto deshabilitado):

1. `Bluray-1080p`  ← **Upgrade until**
2. Grupo `WEB 1080p` = `WEBDL-1080p` + `WEBRip-1080p`

Fuera a propósito: `Remux-1080p` (20–40 GB/película), `HDTV-1080p` (calidad TV),
todo 720p/SD. Si algún día quieres 4K, crea un perfil `ES+VO 2160p` aparte; no
lo mezcles con este.

**Ajustes:**

| Campo | Valor |
| --- | --- |
| Language (solo Radarr) | **Any** (si pones Spanish, Radarr descarta los dual) |
| Upgrades allowed | ✅ |
| Minimum Custom Format Score | **2000** |
| Upgrade Until Custom Format Score | **2100** |
| Minimum score increment | 1 |

**Puntuaciones:**

| CF | Score |
| --- | --- |
| `ES - Castellano` | 1000 |
| `VO - Original/Dual` | 1000 |
| `ES - Solo latino` | -10000 |
| `VOSE` | -10000 |
| `Repack1` / `Repack2` / `Repack3` (Dictionarry) | 5 / 6 / 7 |
| `3D`, `Upscaled`, `Full Disc`, `Extras`, `TV Extras`, `Sing Along` (Dictionarry) | -10000 |

### 5b. Perfil de respaldo `ES 1080p` (castellano obligatorio, VO preferida)

Los trackers públicos españoles publican mucho **solo en castellano**, y con
`ES+VO 1080p` esos títulos se quedan sin descargar. `ES 1080p` descarga la
versión en castellano y la **sustituye sola** por la dual cuando aparece.

La forma más rápida: *Quality Profiles → `ES+VO 1080p` → Clone* (si tu versión
no tiene esa opción, créalo nuevo con los mismos valores) → nombre
`ES 1080p`, y cambia **solo** esto:

| Campo | `ES+VO 1080p` | `ES 1080p` |
| --- | --- | --- |
| Score `ES - Castellano` | 1000 | **1000** |
| Score `VO - Original/Dual` | 1000 | **500** |
| Minimum Custom Format Score | 2000 | **1000** |
| Upgrade Until Custom Format Score | 2100 | **1600** |

Calidades, Language = Any, el resto de puntuaciones (latino, VOSE, 3D, repacks…)
y tamaños: **idénticos** a `ES+VO 1080p`.

Por qué la VO baja a 500: así el castellano es lo único que llega al mínimo por
sí solo. Si dejases VO en 1000 con mínimo 1000, un release **solo en inglés**
también pasaría.

| Release | Puntuación | Resultado |
| --- | --- | --- |
| Dual castellano + inglés | 1500 | ✅ descarga (o upgrade) |
| Solo castellano | 1000 | ✅ descarga, queda pendiente de upgrade |
| Solo inglés / solo VO | 500 | ❌ < 1000 |
| Latino sin castellano / VOSE | ≤ -9500 | ❌ |
| Película española en castellano | 1500 | ✅ (castellano = VO) |

Con el upgrade activo, un fichero solo en castellano (1000) se reemplaza en
cuanto aparezca uno dual (1500) en 1080p; el repack suma unos puntos, por eso el
tope está en 1600 y no en 1500.

**Cuándo usar cada uno:**

- `ES+VO 1080p` → por defecto (Seerr, alta nueva). Solo descarga lo que cumple
  tus dos requisitos.
- `ES 1080p` → para títulos que lleven tiempo en *Wanted/Missing* sin aparecer
  en dual (series de TV en abierto, películas pequeñas…). Cámbialo a mano en esa
  película/serie, o desde el *Movie/Series Editor* para varias a la vez.

> Si prefieres justo lo contrario (tener algo cuanto antes y mejorar después),
> pon `ES 1080p` como perfil por defecto. Ten en cuenta que entonces muchas
> películas se descargan dos veces (castellano → dual).

### 6. Tamaños (*Media Management → Quality Definitions*)

Radarr y Sonarr miden en **MB por minuto** de duración, así el mismo valor vale
para una película de 2 h y un capítulo de 45 min:

| Calidad | Min | Preferido | Max |
| --- | --- | --- | --- |
| `WEBDL-1080p` / `WEBRip-1080p` | 12 | 50 | 110 |
| `Bluray-1080p` | 15 | 70 | 140 |

Equivalencia aproximada:

| Calidad | Película 2 h | Capítulo 45 min | Capítulo 25 min |
| --- | --- | --- | --- |
| WEB 1080p | 1,4 – **6** – 13 GB | 0,5 – **2,2** – 4,9 GB | 0,3 – **1,2** – 2,7 GB |
| Bluray 1080p | 1,8 – **8,4** – 16,8 GB | 0,7 – **3,1** – 6,3 GB | 0,4 – **1,7** – 3,5 GB |

El mínimo es bajo a propósito para no descartar encodes x265 de trackers
españoles (MicroHD, BDRip x265); el preferido hace que, a igualdad de puntuación,
gane el de tamaño medio. Crea una config y asígnala a ambas instancias.

### 7. Resto de Media Management

| Sección | Valor recomendado |
| --- | --- |
| **Media Settings** → Propers & Repacks | **Do not Prefer** (lo decide el CF `Repack*`) |
| Media Settings → Analyse video files | ✅ |
| **Naming** Radarr (película) | `{Movie CleanTitle} ({Release Year}) {tmdb-{TmdbId}} - {Quality Full}{[MediaInfo AudioLanguages]}` |
| Naming Radarr (carpeta) | `{Movie CleanTitle} ({Release Year}) {tmdb-{TmdbId}}` |
| Naming Sonarr (episodio) | `{Series TitleYear} - S{season:00}E{episode:00} - {Episode CleanTitle} [{Quality Full}]{[MediaInfo AudioLanguages]}` |
| Naming Sonarr (carpeta serie) | `{Series TitleYear} {tvdb-{TvdbId}}` |
| Naming Sonarr (temporada) | `Season {season:00}` |

Las etiquetas `{tmdb-…}` / `{tvdb-…}` hacen que Jellyfin identifique el título
sin errores; `AudioLanguages` deja ver en el nombre si el fichero es `[SPA+ENG]`.

### 8. Delay Profile

| Campo | Valor |
| --- | --- |
| Preferred protocol | **Only Torrent** |
| Torrent delay | **120 min** |
| Bypass if highest quality | ✅ |

Da 2 h para que aparezca la versión dual antes de quedarse con la primera; si
ya llega `Bluray-1080p` con 2000 puntos, se descarga al momento.

### 9. Sync

*Arr Instances → radarr / sonarr → Sync*:

- Quality profiles: `ES+VO 1080p` **y** `ES 1080p` (los CF que usan van incluidos).
- Delay profile, Naming, Media Settings y Quality Definitions: los del paso 6–8.
- Programación: cron diario (p.ej. `0 4 * * *`) **y** *on pull*.

Después, en Radarr/Sonarr:

- *Settings → Profiles*: comprueba que aparece `ES+VO 1080p` y ponlo como
  perfil por defecto al añadir (y en **Seerr**, en la config de cada servidor).
- Cambia el perfil de lo que ya tengas en biblioteca (*Movie/Series Editor →
  selecciona todo → Quality Profile*).
- Limpia los perfiles por defecto de Radarr/Sonarr (Any, HD-720p…) y CF
  antiguos: usa *Cleanup* de la instancia en Profilarr (borra de la app lo que
  no está en el Sync) o hazlo a mano en *Settings → Profiles*. Un perfil que aún
  tenga películas/series asignadas no se puede borrar: cámbialas antes.

### 10. Comprobación

En Radarr, abre una película → *Interactive Search*: la columna de puntuación
debe mostrar 2000 para los dual castellano, y los rechazados indicar
*"Custom Formats … score of 1000 is below minimum 2000"*. Con `ES 1080p`, los
solo-castellano deben salir con 1000 y aceptados, y los solo-inglés con 500 y
rechazados. En Profilarr puedes
hacer lo mismo sin tocar Radarr con *Quality Profiles → Testing* (simula un
título de TMDB con releases importados desde la instancia).

---

## Más allá de Profilarr (checklist)

- **qBittorrent**: categorías `radarr` y `sonarr` con ruta en
  `/data_arr/downloads/...`; en Radarr/Sonarr el *Download Client* usa esas
  categorías. Mismo `/data_arr` en todos los contenedores (ya está así) → hardlinks.
- **Root folders**: `/data_arr/media/movies` (Radarr) y `/data_arr/media/tv`
  (Sonarr); *Use Hardlinks instead of Copy* ✅.
- **Bazarr**: perfil de idiomas *Spanish* (+ *English*), con **forced** en
  castellano para los fragmentos en otro idioma; proveedores OpenSubtitles.com,
  Subdivx, Addic7ed.
- **Jellyfin**: en cada usuario, *Reproducción → Idioma de audio preferido* =
  Spanish (o vacío para VO) y subtítulos según preferencia.
- **Unpackerr**: ya configurado en `.env.example` (rutas `/data_arr/downloads`).
