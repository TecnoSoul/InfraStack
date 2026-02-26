# Nextcloud - Guía de Despliegue
## nube.tecnosoul.com.ar · CT210 · venus.ts

---

## Arquitectura

```
Internet
    │
    ▼
NPM CT200 (15.235.57.208)
    │  SSL termination (Let's Encrypt)
    │  nube.tecnosoul.com.ar → 192.168.2.210:8080
    ▼
CT210 - Nextcloud LXC (192.168.2.210)
    ├── Docker: nextcloud:apache   → :8080 (localhost only)
    ├── Docker: nextcloud-cron     → background jobs
    ├── Docker: mariadb:11         → internal
    └── Docker: redis:alpine       → internal

Storage (hdd-pool ZFS):
    hdd-pool/container-data/nextcloud/
    ├── data/    → /var/www/html/data   (archivos de usuarios)
    ├── config/  → /var/www/html/config (config de NC)
    ├── db/      → /var/lib/mysql       (base de datos)
    └── redis/   → /data                (cache)
```

---

## Deploy automático con InfraStack (recomendado)

```bash
# Desde venus.ts como root:
cd /root/InfraStack
./scripts/containers/nextcloud.sh -i 210 -n nube
```

El script hace todo: ZFS dataset, LXC container, Docker, stack completo y credenciales.
Las credenciales quedan en `/root/nextcloud-credentials-ct210.txt` (chmod 600).

Después del script, ir directo a [Fase 5: NPM](#fase-5-configurar-npm-ct200).

---

## Deploy manual paso a paso

### Fase 1: Crear ZFS Dataset (en venus.ts host)

```bash
# Crear dataset en hdd-pool
zfs create \
    -o recordsize=128k \
    -o atime=off \
    -o compression=lz4 \
    hdd-pool/container-data/nextcloud

# Crear estructura de directorios
mkdir -p /hdd-pool/container-data/nextcloud/{data,config,db,redis}

# Permisos para container no privilegiado (uid offset = 100000)
# www-data (uid 33)  → 100033 en host
# mysql    (uid 999) → 100999 en host
chown -R 100033:100033 /hdd-pool/container-data/nextcloud/data
chown -R 100033:100033 /hdd-pool/container-data/nextcloud/config
chown -R 100999:100999 /hdd-pool/container-data/nextcloud/db
chown -R 100999:100999 /hdd-pool/container-data/nextcloud/redis
```

---

### Fase 2: Crear Contenedor LXC

```bash
pct create 210 local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
    --hostname nube.tecnosoul.com.ar \
    --description "Nextcloud - nube.tecnosoul.com.ar" \
    --cores 4 \
    --memory 4096 \
    --swap 2048 \
    --rootfs data:20 \
    --unprivileged 1 \
    --features nesting=1,keyctl=1 \
    --net0 name=eth0,bridge=vmbr1,ip=192.168.2.210/24,gw=192.168.2.1 \
    --nameserver 8.8.8.8 \
    --searchdomain tecnosoul.com.ar \
    --ostype debian \
    --start 0

# Montar el dataset ZFS en el contenedor
pct set 210 --mp0 /hdd-pool/container-data/nextcloud,mp=/mnt/nextcloud-data

# Iniciar
pct start 210
```

---

### Fase 3: Setup inicial del CT

```bash
pct exec 210 -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get dist-upgrade -y -qq
    timedatectl set-timezone America/Argentina/Buenos_Aires
"
```

---

### Fase 4: Instalar Docker

```bash
pct exec 210 -- bash -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
        https://download.docker.com/linux/debian \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    systemctl enable docker && systemctl start docker
    docker --version
'
```

---

### Fase 5 (manual): Deploy del stack

```bash
# Crear directorio de la app en el CT
pct exec 210 -- bash -c "mkdir -p /opt/nextcloud"

# Copiar el docker-compose.yml de referencia al CT
pct push 210 docs/nextcloud/docker-compose.yml /opt/nextcloud/docker-compose.yml

# Crear .env con passwords seguros
cat > /tmp/nextcloud.env << EOF
DB_ROOT_PASSWORD=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32)
DB_PASSWORD=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32)
NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)
EOF
pct push 210 /tmp/nextcloud.env /opt/nextcloud/.env
pct exec 210 -- chmod 600 /opt/nextcloud/.env

# Arrancar el stack
pct exec 210 -- bash -c "cd /opt/nextcloud && docker compose up -d"

# Seguir el primer arranque (~2 minutos)
pct exec 210 -- docker compose -f /opt/nextcloud/docker-compose.yml logs -f nextcloud
# Listo cuando aparece: "apache2 -D FOREGROUND"
```

---

## Fase 5: Configurar NPM (CT200)

### DNS primero
```
nube.tecnosoul.com.ar.  A  15.235.57.208
```

### En NPM (http://15.235.57.208:81) → Add Proxy Host

| Campo | Valor |
|---|---|
| Domain Names | `nube.tecnosoul.com.ar` |
| Scheme | `http` |
| Forward Hostname / IP | `192.168.2.210` |
| Forward Port | `8080` |
| Cache Assets | ✅ |
| Block Common Exploits | ✅ |
| Websockets Support | ✅ |

**SSL tab:**
- SSL Certificate: Let's Encrypt
- Force SSL: ✅
- HTTP/2 Support: ✅

**Advanced tab** (requerido para Nextcloud):
```nginx
client_max_body_size 10G;
client_body_timeout 3600s;

proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-Proto $scheme;
```

---

## Fase 6: Post-instalación Nextcloud

```bash
pct exec 210 -- bash -c "
    # Verificar config del reverse proxy (debe retornar: https)
    docker exec -u www-data nextcloud-app php occ config:system:get overwriteprotocol

    # Activar cron como método de background jobs
    docker exec -u www-data nextcloud-app php occ background:cron

    # Agregar trusted proxy (IP del NPM en la red interna)
    docker exec -u www-data nextcloud-app php occ config:system:set \
        trusted_proxies 0 --value='192.168.2.200'

    # Verificar estado general
    docker exec -u www-data nextcloud-app php occ status
    docker exec -u www-data nextcloud-app php occ check
"
```

---

## Comandos de gestión

```bash
# Entrar al CT
pct enter 210
cd /opt/nextcloud

# Ver logs
docker compose logs -f nextcloud
docker compose logs -f db

# Reiniciar stack
docker compose restart

# Actualizar Nextcloud
docker compose pull
docker compose up -d
docker exec -u www-data nextcloud-app php occ upgrade

# Modo mantenimiento
docker exec -u www-data nextcloud-app php occ maintenance:mode --on
docker exec -u www-data nextcloud-app php occ maintenance:mode --off

# Backup manual DB
docker exec nextcloud-db mysqldump -u nextcloud -p nextcloud > \
    /mnt/nextcloud-data/backup-$(date +%Y%m%d).sql

# Escanear archivos (si se suben manualmente al ZFS)
docker exec -u www-data nextcloud-app php occ files:scan --all
```

---

## Backup

```bash
# Backup completo del CT (desde venus host)
vzdump 210 --storage hdd-backups --compress zstd --mode snapshot

# Snapshot ZFS del dataset de datos (antes de updates)
zfs snapshot hdd-pool/container-data/nextcloud@before-update-$(date +%Y%m%d)
zfs list -t snapshot | grep nextcloud
```

---

## Troubleshooting

**Nextcloud no arranca / error de DB:**
```bash
docker compose logs db
# Si hay error de permisos en /var/lib/mysql (ejecutar en venus HOST, no en el CT):
chown -R 100999:100999 /hdd-pool/container-data/nextcloud/db
```

**Error 413 Request Entity Too Large:**
```
→ Agregar en NPM Advanced: client_max_body_size 10G;
```

**"Untrusted domain" al acceder:**
```bash
docker exec -u www-data nextcloud-app php occ config:system:set \
    trusted_domains 1 --value="nube.tecnosoul.com.ar"
```

**Warnings de salud en el panel de admin:**
```bash
docker exec -u www-data nextcloud-app php occ db:add-missing-indices
docker exec -u www-data nextcloud-app php occ db:convert-filecache-bigint
docker exec -u www-data nextcloud-app php occ status
docker exec -u www-data nextcloud-app php occ check
```
