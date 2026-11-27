# n8n-ai - Guía de Despliegue
## n8n.example.com · CT220

La guía completa vive junto al stack, en [`stacks/n8n-ai/README.md`](../../stacks/n8n-ai/README.md),
para que se versione con el compose. Esta página resume la arquitectura y los comandos.

---

## Arquitectura

### Opción A (recomendada): Cloudflare Tunnel + Access

```
Navegador
    │  login de Cloudflare Access (mail con código, Google, GitHub…)
    ▼
Cloudflare (borde)  ── TLS, DNS y política de Access
    ▲
    │  túnel saliente: sin puertos abiertos en el host ni en el CT
    │
CT220 - n8n-ai LXC (192.168.2.220)
    └── Docker (/opt/n8n-ai)
          ├── cloudflared   → http://n8n:5678
          ├── n8n           → 127.0.0.1:5678 (solo dentro del CT)
          ├── n8n-runner    (Code node aislado)
          └── postgres      (pgvector, volumen Docker en NVMe)
```

### Opción B: NPM

```
Internet
    │
    ▼
NPM CT200 (203.0.113.20)
    │  SSL termination (Let's Encrypt) + access list por IP
    │  n8n.example.com → 192.168.2.220:5678
    ▼
CT220 - n8n-ai LXC (192.168.2.220)
    └── Docker (/opt/n8n-ai): n8n · n8n-runner · postgres
```

En los dos casos los datos están en volúmenes Docker sobre el disco raíz (NVMe); no usa `hdd-pool`.

---

## Despliegue

### Opción A: Cloudflare Tunnel + Access

Requiere que el dominio tenga el DNS en Cloudflare. Usar un subdominio de primer nivel
(`n8n.example.com`): el certificado gratuito no cubre niveles más profundos.

1. **Zero Trust → Networks → Tunnels → Create a tunnel** (Cloudflared). Copiar el token.
2. **Access → Applications → Add → Self-hosted**: dominio `n8n.example.com`, política *Allow*
   con los mails del equipo. Hacerlo **antes** del paso 4.
3. En el host Proxmox:

   ```bash
   install -m 600 /dev/null /root/n8n-tunnel.token && nano /root/n8n-tunnel.token
   infrastack containers n8n-ai -i 220 -n n8n --domain n8n.example.com \
     --tunnel-token-file /root/n8n-tunnel.token
   ```

4. En el túnel → **Public hostname**: `n8n.example.com` → servicio `http://n8n:5678`.
5. Abrir `https://n8n.example.com`, pasar el login de Access, crear la cuenta owner de n8n y activar 2FA.

### Opción B: NPM

```bash
infrastack containers n8n-ai -i 220 -n n8n --domain n8n.example.com
```

Después: registro DNS hacia la IP pública de NPM, proxy host con Websockets y Let's Encrypt,
access list con las IPs del equipo y `location /metrics { deny all; return 404; }` en *Advanced*.
El resumen del script imprime los valores exactos.

---

## Después del despliegue

- Copiar `N8N_ENCRYPTION_KEY` de `/root/n8n-ai-credentials-ct220.txt` (host) a Vaultwarden.
- Verificar: `pct exec 220 -- bash -c 'cd /opt/n8n-ai && docker compose ps'`
  (y `docker compose logs cloudflared` en la opción A).
- Operación (actualizar, backups, exportar flujos) y el primer flujo de práctica:
  ver [`stacks/n8n-ai/README.md`](../../stacks/n8n-ai/README.md).

## Cambiar de opción

- **A → B**: primero `docker compose --profile tunnel stop cloudflared && docker compose --profile tunnel rm -f cloudflared`
  (con el profile desactivado, compose ya no lo gestiona); después, en `/opt/n8n-ai/.env`,
  `COMPOSE_PROFILES=` y `N8N_BIND_ADDR=0.0.0.0`; `docker compose up -d`; configurar NPM y el firewall.
- **B → A**: crear el túnel y la aplicación de Access; en `.env`, `COMPOSE_PROFILES=tunnel`,
  `N8N_BIND_ADDR=127.0.0.1` y `CLOUDFLARE_TUNNEL_TOKEN=<token>`; `docker compose up -d`;
  borrar el proxy host de NPM.
