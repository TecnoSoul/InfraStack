# Vaultwarden - Guía de Despliegue
## vault.tecnosoul.com.ar · CT211 · venus.ts

---

## Arquitectura

```
Internet
    │
    ▼
NPM CT200 (15.235.57.208)
    │  SSL termination (Let's Encrypt)
    │  vault.tecnosoul.com.ar → 192.168.2.211:8080
    ▼
CT211 - Vaultwarden LXC (192.168.2.211)
    └── Docker: vaultwarden/server:latest → 127.0.0.1:8080 (localhost only)
                SQLite (incluido en la imagen)

Storage (hdd-pool ZFS):
    hdd-pool/container-data/vaultwarden/
    └── (raíz del dataset) → /mnt/vaultwarden-data
          ├── db.sqlite3        (base de datos)
          ├── attachments/      (adjuntos de vault entries)
          ├── sends/            (Bitwarden Send files)
          └── config.json       (config interna)
```

---

## Deploy automático con InfraStack (recomendado)

```bash
# Desde venus.ts como root:
cd /root/InfraStack
./scripts/containers/vaultwarden.sh -i 211 -n vault
```

El script hace todo: ZFS dataset, LXC container, Docker, stack completo y credenciales.
Las credenciales (admin token) quedan en `/root/vaultwarden-credentials-ct211.txt` (chmod 600).

Después del script, ir directo a [NPM: Configurar Proxy Host](#npm-configurar-proxy-host).

---

## Deploy manual paso a paso

### Fase 1: Crear ZFS Dataset (en venus.ts host)

```bash
# Crear dataset con recordsize pequeño (SQLite se beneficia de bloques chicos)
zfs create \
    -o recordsize=16k \
    -o atime=off \
    -o compression=lz4 \
    hdd-pool/container-data/vaultwarden

mkdir -p /hdd-pool/container-data/vaultwarden

# Permisos para container no privilegiado
# Vaultwarden corre como nobody (uid 65534)
# Unprivileged LXC offset: 100000 + 65534 = 165534
chown -R 165534:165534 /hdd-pool/container-data/vaultwarden
```

---

### Fase 2: Crear Contenedor LXC

```bash
pct create 211 local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
    --hostname vault.tecnosoul.com.ar \
    --description "Vaultwarden - vault.tecnosoul.com.ar" \
    --cores 2 \
    --memory 512 \
    --swap 256 \
    --rootfs data:8 \
    --unprivileged 1 \
    --features nesting=1,keyctl=1 \
    --net0 name=eth0,bridge=vmbr1,ip=192.168.2.211/24,gw=192.168.2.1 \
    --nameserver 8.8.8.8 \
    --searchdomain tecnosoul.com.ar \
    --ostype debian \
    --start 0

# Montar el dataset ZFS en el contenedor
pct set 211 --mp0 /hdd-pool/container-data/vaultwarden,mp=/mnt/vaultwarden-data

# Iniciar
pct start 211
```

---

### Fase 3: Setup inicial del CT

```bash
pct exec 211 -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get dist-upgrade -y -qq
    timedatectl set-timezone America/Argentina/Buenos_Aires
"
```

---

### Fase 4: Instalar Docker

```bash
pct exec 211 -- bash -c '
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

### Fase 5: Deploy de Vaultwarden

```bash
# Generar admin token
ADMIN_TOKEN=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48)
echo "Admin token: $ADMIN_TOKEN"   # Guardar este valor

# Crear directorio de la app en el CT
pct exec 211 -- mkdir -p /opt/vaultwarden

# Escribir docker-compose.yml
pct exec 211 -- bash -c "cat > /opt/vaultwarden/docker-compose.yml << 'EOF'
services:

  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    ports:
      - \"127.0.0.1:8080:80\"
    environment:
      DOMAIN: https://vault.tecnosoul.com.ar
      ADMIN_TOKEN: REEMPLAZAR_CON_TOKEN
      SIGNUPS_ALLOWED: \"true\"
      INVITATIONS_ALLOWED: \"true\"
      WEBSOCKET_ENABLED: \"true\"
      LOG_LEVEL: warn
      EXTENDED_LOGGING: \"true\"
      TZ: America/Argentina/Buenos_Aires
    volumes:
      - /mnt/vaultwarden-data:/data
EOF"

# Reemplazar el token placeholder con el real
pct exec 211 -- sed -i "s/REEMPLAZAR_CON_TOKEN/${ADMIN_TOKEN}/" /opt/vaultwarden/docker-compose.yml

# Arrancar Vaultwarden
pct exec 211 -- bash -c "cd /opt/vaultwarden && docker compose up -d"

# Verificar que levantó
pct exec 211 -- docker ps
```

---

## NPM: Configurar Proxy Host

### DNS primero
```
vault.tecnosoul.com.ar.  A  15.235.57.208
```

### En NPM (http://15.235.57.208:81) → Add Proxy Host

| Campo | Valor |
|---|---|
| Domain Names | `vault.tecnosoul.com.ar` |
| Scheme | `http` |
| Forward Hostname / IP | `192.168.2.211` |
| Forward Port | `8080` |
| Cache Assets | ❌ (no aplica para password manager) |
| Block Common Exploits | ✅ |
| Websockets Support | ✅ (requerido para live sync entre clientes) |

**SSL tab:**
- SSL Certificate: Let's Encrypt
- Force SSL: ✅
- HTTP/2 Support: ✅

---

## Post-instalación

### 1. Crear cuenta de usuario

Ir a `https://vault.tecnosoul.com.ar` y crear la cuenta principal mientras el registro está abierto.

### 2. Deshabilitar registro

Después de crear tu cuenta, cerrar el registro:

```bash
# Editar docker-compose.yml
pct exec 211 -- sed -i 's/SIGNUPS_ALLOWED: "true"/SIGNUPS_ALLOWED: "false"/' \
    /opt/vaultwarden/docker-compose.yml

# Reiniciar para aplicar el cambio
pct exec 211 -- bash -c "cd /opt/vaultwarden && docker compose restart"
```

### 3. Verificar admin panel

Acceder a `https://vault.tecnosoul.com.ar/admin` con el token guardado en
`/root/vaultwarden-credentials-ct211.txt`.

---

## Comandos de gestión

```bash
# Entrar al CT
pct enter 211
cd /opt/vaultwarden

# Ver logs
docker compose logs -f

# Reiniciar stack
docker compose restart

# Actualizar Vaultwarden
docker compose pull
docker compose up -d

# Ver estado de contenedores
docker ps

# Ver uso de disco del vault
du -sh /mnt/vaultwarden-data/
```

---

## Backup

```bash
# Backup completo del CT (desde venus host)
vzdump 211 --storage hdd-backups --compress zstd --mode snapshot

# Snapshot ZFS del dataset (antes de updates)
zfs snapshot hdd-pool/container-data/vaultwarden@before-update-$(date +%Y%m%d)
zfs list -t snapshot | grep vaultwarden

# Rollback a snapshot
zfs rollback hdd-pool/container-data/vaultwarden@before-update-20260226
```

> **Nota:** El archivo `db.sqlite3` en `/mnt/vaultwarden-data/` es la única fuente de verdad.
> El snapshot ZFS captura este archivo de forma consistente cuando el CT está detenido.
> Para backup en caliente, Vaultwarden genera automáticamente `db.sqlite3.bak` (copia diaria).

---

## Troubleshooting

**Vaultwarden no arranca:**
```bash
docker compose logs vaultwarden
# Verificar permisos del mountpoint:
ls -la /mnt/vaultwarden-data/
# Deben ser del usuario nobody (uid 65534 dentro del CT)
```

**Error de permisos en /mnt/vaultwarden-data (desde venus HOST):**
```bash
chown -R 165534:165534 /hdd-pool/container-data/vaultwarden
```

**No llegan los WebSockets (clientes no sincronizan en tiempo real):**
```
→ Verificar que NPM tiene Websockets Support: ✅
→ Verificar WEBSOCKET_ENABLED: "true" en docker-compose.yml
```

**HTTPS requerido para funcionar correctamente:**
Vaultwarden requiere HTTPS para funciones como WebAuthn y acceso desde apps móviles.
Sin SSL, el acceso web funciona pero con limitaciones. Siempre configurar NPM primero.

**Agregar usuario adicional (con registro cerrado):**
```bash
# Opción A: Reabrir registro temporalmente
pct exec 211 -- sed -i 's/SIGNUPS_ALLOWED: "false"/SIGNUPS_ALLOWED: "true"/' \
    /opt/vaultwarden/docker-compose.yml
pct exec 211 -- bash -c "cd /opt/vaultwarden && docker compose restart"
# ... el usuario crea su cuenta ...
# Cerrar nuevamente:
pct exec 211 -- sed -i 's/SIGNUPS_ALLOWED: "true"/SIGNUPS_ALLOWED: "false"/' \
    /opt/vaultwarden/docker-compose.yml
pct exec 211 -- bash -c "cd /opt/vaultwarden && docker compose restart"

# Opción B: Invitación desde el admin panel
# https://vault.tecnosoul.com.ar/admin → Users → Invite User
```
