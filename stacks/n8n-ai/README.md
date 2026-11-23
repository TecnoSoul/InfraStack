# stack n8n-ai

Automatización con [n8n](https://n8n.io) + modelos de IA por API, self-hosted en un LXC de Proxmox.
Es parte de InfraStack: uso interno real y, a la vez, laboratorio para aprender las herramientas
que se usan hoy al integrar IA en proyectos.

> **Licencias.** Este directorio (compose, scripts, flujos exportados) es MIT, como el resto de
> InfraStack. n8n en sí es *fair-code* (Sustainable Use License), no open source OSI: está
> permitido para uso interno; no para revenderlo ni hostearlo para terceros.

## Fases

| Fase | Qué agrega | Para aprender |
|------|------------|---------------|
| 0 | n8n + task runner + Postgres (pgvector) | editor, nodos, items, credenciales, ejecuciones |
| 1 | profile `ai`: LiteLLM como gateway | llamar a un modelo, salida JSON, timeouts, topes de gasto |
| 2 | flujo "resumen diario de monitoreo" | anonimización, validación, fallback sin IA |
| 3 | profile `chat`: Open WebUI sobre el gateway | chat interno, RAG sobre runbooks con pgvector |
| 4 | MCP: flujos de n8n como herramientas | agentes que consultan nuestros sistemas (solo lectura) |
| 5 | profile `local`: Ollama | comparar calidad, latencia y costo contra la API |

## Requisitos

- LXC Debian 13 **no privilegiado** con `nesting=1,keyctl=1` y Docker
  (mismo patrón que `scripts/containers/vaultwarden.sh`).
- ~2 GB de RAM y 20 GB de disco para la fase 0.
- Acceso: Cloudflare Tunnel + Access (recomendado, ver abajo) o NPM con HTTPS delante.

## Levantar

### Con InfraStack (Proxmox)

Desde el host Proxmox, con `INFRASTACK_DOMAIN` (o `N8N_DOMAIN`) en `/etc/infrastack/infrastack.conf`:

```bash
# Con Cloudflare Tunnel (recomendado): el token en un archivo, nunca como argumento
install -m 600 /dev/null /root/n8n-tunnel.token && nano /root/n8n-tunnel.token
infrastack containers n8n-ai -i 220 -n n8n --domain n8n.example.com \
  --tunnel-token-file /root/n8n-tunnel.token

# Con NPM
infrastack containers n8n-ai -i 220 -n n8n
# opcional en ambos: --n8n-version <tag> -c 2 -m 2048
```

Crea el CT, instala Docker, copia este directorio a `/opt/n8n-ai`, genera `.env`, levanta el
stack y deja una copia de los secretos en `/root/n8n-ai-credentials-ct<ctid>.txt` del host.

### A mano (cualquier host con Docker)

```bash
cp -r stacks/n8n-ai /opt/n8n-ai && cd /opt/n8n-ai   # fuera del checkout: .env no se versiona
scripts/gen-env.sh --host n8n.example.com                 # modo NPM
# o: scripts/gen-env.sh --host n8n.example.com --tunnel-token-file /ruta/al/token
# Revisar .env: N8N_VERSION (fijar la última estable), y guardar N8N_ENCRYPTION_KEY en Vaultwarden
docker compose up -d
docker compose ps                        # postgres y n8n deben quedar "healthy"
docker compose logs -f n8n
```

Para actualizar el compose desde el repo: `diff -r stacks/n8n-ai /opt/n8n-ai` y copiar lo que cambió.

Primera vez sin proxy, para probar desde la LAN: `N8N_SECURE_COOKIE=false` y entrar a
`http://<ip-del-ct>:5678`. Volver a `true` cuando esté detrás de HTTPS.

Al entrar por primera vez, n8n pide crear la cuenta *owner*: hacerlo enseguida
(quien llegue primero se queda con la instancia) y activar 2FA en *Settings → Personal*.

## Acceso

### Opción A (recomendada): Cloudflare Tunnel + Access

El contenedor `cloudflared` (profile `tunnel`) abre una conexión **saliente** hacia Cloudflare:
no hay puertos abiertos, n8n queda atado a `127.0.0.1` y, antes de llegar al editor,
Cloudflare Access pide login (código por mail, Google, GitHub…). Funciona desde cualquier IP,
sin VPN. Requiere que el dominio tenga el DNS en Cloudflare; el plan gratuito de Zero Trust alcanza
para equipos chicos.

1. **Crear el túnel**: Zero Trust → *Networks → Tunnels → Create a tunnel* → Cloudflared.
   Copiar el token (la cadena larga del comando `cloudflared service install <token>`)
   a un archivo con permisos 600. No hace falta instalar nada a mano: lo corre el compose.
2. **Crear la aplicación de Access primero**: *Access → Applications → Add → Self-hosted*,
   dominio `n8n.example.com`, política *Allow* con los mails del equipo. Hacerlo **antes** del
   paso 3 para que el hostname nunca quede publicado sin login.
3. **Publicar el hostname**: en el túnel → *Public hostname* → `n8n.example.com` →
   servicio `http://n8n:5678`. Cloudflare crea el registro DNS.
4. Levantar el stack (`gen-env.sh --tunnel-token-file …` o el script de InfraStack) y revisar
   `docker compose logs cloudflared`: tiene que mostrar conexiones registradas.

Notas:

- Usar subdominios de **primer nivel** (`n8n.example.com`, no `n8n.ops.example.com`):
  el certificado gratuito de Cloudflare cubre solo ese nivel.
- Cloudflare termina TLS en su borde y ve el tráfico del editor. Para una herramienta interna
  es aceptable, pero es una decisión de privacidad: tenerla presente.
- Access protege todas las rutas, `/metrics` incluido. Para webhooks públicos (formularios, etc.)
  se publica más adelante otro hostname (`hooks.example.com`) con una política *Bypass* limitada
  a `/webhook/*`, y `WEBHOOK_URL` apuntando a él.
- Salir de Cloudflare es reversible: vaciar `COMPOSE_PROFILES`, `N8N_BIND_ADDR=0.0.0.0` y usar la opción B.

### Opción B: NPM (u otro reverse proxy)

- Proxy host `n8n.example.com` → `http://<ip-del-ct>:5678`, Websockets **on**, SSL Let's Encrypt.
- **Access list**: solo las IPs del equipo.
- En *Advanced*, no exponer las métricas:

  ```nginx
  location /metrics { deny all; return 404; }
  ```

- Firewall del CT: que al puerto 5678 solo llegue la IP del CT de NPM.

## Operación

| Tarea | Cómo |
|-------|------|
| Actualizar | cambiar `N8N_VERSION` en `.env` → `docker compose pull && docker compose up -d` (leer el changelog antes) |
| Backup de la base | `docker compose exec postgres pg_dump -U postgres n8n \| gzip > backups/n8n-$(date +%F).sql.gz` |
| Backup del CT | `vzdump` a `hdd-backups`, como el resto |
| Exportar flujos a git | `docker compose exec n8n n8n export:workflow --all --separate --output=/home/node/.n8n/export/` y después `docker compose cp n8n:/home/node/.n8n/export/. workflows/`. Revisar los JSON antes de commitear: las credenciales van solo por referencia, pero URLs, hostnames o datos fijados (*pin data*) pueden quedar adentro |
| Salud | `/healthz` en Uptime Kuma |

## Flujo de juguete: "novedades de InfraStack"

Sin IA, para aprender el editor. Cada día lista los commits nuevos del repo y avisa.

1. **Schedule Trigger**: cada día a las 9:00. Mientras lo armás, usá *Execute workflow* a mano.
2. **HTTP Request**: `GET https://api.github.com/repos/TecnoSoul/InfraStack/commits`
   con el query param `since` = `{{ $now.minus({ days: 1 }).toISO() }}` (una *expresión*).
   La API devuelve un array: n8n lo convierte en un *item* por commit.
3. **IF**: ¿llegó al menos un item? Si no, termina sin avisar.
4. **Code** (JavaScript): junta todos los items en un solo mensaje:

   ```js
   const commits = $input.all().map(i =>
     `• ${i.json.commit.message.split('\n')[0]} (${i.json.commit.author.name})`);
   return [{ json: { text: `InfraStack: ${commits.length} commit(s) en 24 h\n${commits.join('\n')}` } }];
   ```

5. **Salida**: Telegram, mail o un *No Op* para ver el resultado mientras se decide el canal.
6. **Pin data** en el nodo HTTP: fijar una respuesta de ejemplo para seguir probando sin pegarle a la API.
7. **Error Workflow**: un segundo flujo con *Error Trigger* que avise si este falla;
   asignarlo en *Settings* del flujo principal.
8. **Exportar** el flujo a `workflows/` y commitear.

Conceptos que aparecen: trigger, expresiones `{{ }}`, items, ramas, Code node (corre en `n8n-runner`),
credenciales, historial de ejecuciones, pin data, exportación a git.
