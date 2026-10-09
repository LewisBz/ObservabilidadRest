# ObservabilidadRest

Stack de observabilidad desacoplado para el API REST en un VPS Ubuntu (Hostinger KVM 8: 8 vCPU, 32 GB RAM, 400 GB NVMe). Convive con otros contenedores: **métricas y logs de aplicación solo del REST**; **Node Exporter y cAdvisor miden el hardware del VPS** (incluye el consumo de CPU/RAM/red/I/O de todos los contenedores, sin leer su lógica ni sus logs).

Grafana, Prometheus, Loki, Grafana Alloy, Node Exporter y cAdvisor viven en este repositorio. auditd, AIDE, snoopy y tlog se instalan en el host con scripts aparte. Tempo/OTLP y Cockpit quedan fuera.

## Árbol

```
.
├── docker-compose.yml
├── .env.example
├── prometheus/
│   ├── prometheus.yml
│   ├── targets/rest.yml
│   └── rules/vps.yml
├── loki/loki-config.yaml
├── alloy/config.alloy
├── grafana/provisioning/
│   ├── datasources/datasources.yaml
│   ├── dashboards/dashboards.yaml
│   └── alerting/
├── grafana/dashboards/          # JSON opcionales; el provider ya apunta aquí
├── k6/smoke.js
└── host/                        # no forma parte de docker compose up
    ├── install-host-audit.sh
    ├── init-aide-baseline.sh
    ├── auditd/
    ├── aide/
    ├── snoopy/
    └── tlog/
```

## Presupuesto en el KVM 8

El stack está limitado a unos **6 GB de RAM y 4 vCPU**. El resto queda para Ubuntu y los tres proyectos.

| Servicio       | RAM    | CPU  |
|----------------|--------|------|
| Prometheus     | 2G     | 1.50 |
| Loki           | 2G     | 1.00 |
| Grafana        | 512M   | 0.50 |
| Alloy          | 512M   | 0.50 |
| cAdvisor       | 512M   | 0.50 |
| Node Exporter  | 128M   | 0.25 |

Retención: Prometheus 15 días y tope 20 GB; Loki 15 días, ingesta máxima ~8 MB/s. El scrapeo es interno al VPS; el ancho de banda de 32 TB no entra en el diseño.

## Despliegue

En el VPS, con Docker Compose v2. La red `rest-edge` la crea el gateway REST; no hace falta `docker network create`:

```bash
git clone <este-repo> && cd ObservabilidadRest
cp .env.example .env
# Editar GF_SECURITY_ADMIN_PASSWORD y los GID:
#   getent group docker | cut -d: -f3
#   getent group systemd-journal | cut -d: -f3
#   getent group adm | cut -d: -f3

docker compose up -d
```

Si `rest-edge` no existe (gateway REST apagado), Compose falla a propósito.

Grafana escucha solo en `127.0.0.1:3000`. Acceso remoto:

```bash
ssh -L 3000:127.0.0.1:3000 user@vps
```

Prometheus, Loki, Alloy, cAdvisor y node-exporter no publican puerto al host. No uses 80 ni 443 (son del Nginx del gateway). Un dominio `grafana.restapp.site` sería otro `server` en las plantillas Nginx del REST hacia Grafana por `rest-edge`, no un segundo proceso en 80.

Sincronizar el reloj del VPS (`chrony` o `systemd-timesyncd`): auditd y las métricas tienen que coincidir en hora.

## Puertos

En el VPS solo importan los puertos publicados en el host. El orquestador REST publica **80 y 443**. Express, Flutter, admin, Postgres, Ollama y sentimiento viven dentro de Docker (`expose`, no `ports`).

| Destino | Host | Interno Docker |
|---------|------|----------------|
| Nginx del gateway | 80, 443 | 80 |
| Grafana (este stack) | 127.0.0.1:3000 | 3000 |
| Express prod / pruebas | no publicado | 3000 (`prodbackend`, `testbackend`) |
| Flutter y admin | no publicado | 80 |
| Postgres / Ollama / sentimiento | no publicado | 5432 / 11434 / 8000 |
| Prometheus / Loki / Alloy / cAdvisor / node-exporter | no publicado | 9090 / 3100 / 12345 / 8080 / 9100 |

El 3000 de Grafana en loopback no choca con el 3000 del Express. El 8080 de cAdvisor queda en la red `observability`; no choca con el orquestador.

**Choque si se levantan los Compose sueltos de cada repo** (el README de REST dice que no en el VPS): `backend/docker-compose.yml` publica 3000 (API) y 5433/11434; `admin` publica 8080; `app` publica 8081. Eso sí pisa Grafana y, si alguien publicara cAdvisor, el 8080.

## Contrato en el Compose del REST

Este repositorio no modifica el proyecto REST. El backend ya está en `rest-edge` con alias `prodbackend` y `testbackend`. No hace falta `monitoring_net`. En el servicio **backend** (no Postgres, no Ollama) hay que pegar labels:

```yaml
services:
  backend:
    labels:
      observability: "enabled"
      environment: "develop"   # o "production"
```

Requisitos:

- `/metrics` en el mismo puerto interno **3000** que `/health`. No publicarlo en el host.
- Logs JSON en stdout.
- Sin `/metrics` el job `rest` queda en `DOWN`.

## Capas

**Aplicación REST** (`job=rest`, logs `job=docker`): scrape de `testbackend:3000` y `prodbackend:3000`, logs solo con `observability=enabled`.

**Hardware VPS** (`job=node-exporter`, `job=cadvisor`): CPU, RAM, disco y red del Ubuntu, y uso de recursos de **cada** contenedor del host. Los otros dos proyectos aparecen aquí como nombre de contenedor y consumo, no como logs ni `/metrics` de negocio.

## Dashboards

Datasources Prometheus y Loki se provisionan solos (UID `prometheus` y `loki`). Importar a mano en Grafana:

- Node Exporter Full: [1860](https://grafana.com/grafana/dashboards/1860)
- cAdvisor: buscar “Docker Cadvisor” en grafana.com
- Loki: “Loki dashboard” o explorar `{job="docker"}`, `{job="auditd"}`, `{job="ssh"}`

Dejar JSON propios en `grafana/dashboards/`.

## Alertas

Reglas mínimas (target caído, disco &lt; 15 %, RAM disponible &lt; 10 %) en Prometheus y en Grafana. El destino (Telegram, correo) no está cableado: las alertas se ven en la UI. Para un webhook, copiar `grafana/provisioning/alerting/contactpoints.yaml.example` a `contactpoints.yaml` y poner la URL.

## k6

Apagado por defecto. Humo contra `testbackend:3000` (no contra `prodbackend`):

```bash
docker compose --profile loadtest run --rm k6
```

`K6_TARGET` y `K6_PATH` salen de `.env`.

## Auditoría de host

Independiente de Compose:

```bash
chmod +x host/install-host-audit.sh host/init-aide-baseline.sh
sudo ./host/install-host-audit.sh
sudo ./host/init-aide-baseline.sh    # I/O alto; una vez, fuera de pico
```

| Pregunta | Fuente |
|----------|--------|
| ¿Quién entró y a qué hora? | journal `job=ssh` (y `job=tlog` si esa cuenta graba sesión) |
| ¿Qué comando ejecutó? | snoopy (`job=snoopy`); si el binario evade `LD_PRELOAD`, auditd `execve` (`job=auditd`) |
| ¿Qué archivo de `/etc` cambió en el momento? | reglas auditd |
| ¿Qué cambió respecto al baseline? | `/var/log/aide/aide-check.log` (no es tiempo real) |

tlog se activa **por usuario**, nunca en root ni con `ForceCommand` global:

```bash
sudo usermod -s /usr/bin/tlog-rec-session USUARIO_ADMIN
```

Las grabaciones van al journal; Loki indexa metadatos, no el replay TTY. auditd se entrega con `-e 1`. Cuando las reglas estén estables, se puede pasar a `-e 2` (hace falta reboot para volver a editarlas).

**Cockpit no se instala.** Si ya está, déjalo en localhost o detrás de túnel SSH.

## cAdvisor

Es el servicio con más privilegio (`privileged: true` y montajes del host). Solo se usa para cgroups/Docker. Si `gcr.io` no responde en el VPS, cambiar la imagen a `ghcr.io/google/cadvisor:v0.52.1`.

## Backup

No hay backup remoto de volúmenes. Opciones: snapshot del VPS en Hostinger, o `docker run` que archive `grafana_data`, `prometheus_data`, `loki_data` y `alloy_data`.

## Huecos abiertos a propósito

- La API tiene que exponer `/metrics` (Micrometer/Prometheus client).
- Tempo/OTLP cuando la API emita trazas.
- Probe externo (blackbox) y destino real de alertas.
- Los otros dos proyectos siguen opacos a nivel de aplicación; cAdvisor solo muestra su consumo de máquina.
