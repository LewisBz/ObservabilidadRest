# Despliegue HTTPS en el puerto 8443

Este despliegue es aditivo: no sustituye ni modifica `docker-compose.yml`.
Nginx publica Grafana en:

```text
https://grafana.restapp.site:8443
```

Los puertos 80 y 443 continúan perteneciendo al gateway REST. Certbot reutiliza
únicamente su volumen webroot para completar el desafío HTTP-01; no conecta la
pila de observabilidad a ninguna red adicional.

## Preparación

Combinar las variables existentes con las variables HTTPS en el `.env` privado:

```bash
cd /opt/observabilidad-rest
cp -n .env.example .env

grep -q '^GRAFANA_DOMAIN=' .env || echo 'GRAFANA_DOMAIN=grafana.restapp.site' >> .env
grep -q '^HTTPS_PORT=' .env || echo 'HTTPS_PORT=8443' >> .env
grep -q '^LETSENCRYPT_EMAIL=' .env || echo 'LETSENCRYPT_EMAIL=CORREO_REAL' >> .env
grep -q '^GATEWAY_CERTBOT_WEBROOT_VOLUME=' .env || \
  echo 'GATEWAY_CERTBOT_WEBROOT_VOLUME=rest-gateway_certbot_www' >> .env
```

Reemplazar `CORREO_REAL` y configurar una contraseña fuerte para
`GF_SECURITY_ADMIN_PASSWORD`.

## Certificado inicial

Confirmar primero que el volumen y el DNS existen:

```bash
docker volume inspect rest-gateway_certbot_www >/dev/null
getent ahostsv4 grafana.restapp.site
```

Emitir el certificado antes de iniciar Nginx:

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f docker-compose.https.yml \
  --profile ssl run --rm certbot
```

## Inicio y validación

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f docker-compose.https.yml \
  config --quiet

docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f docker-compose.https.yml \
  up -d

docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f docker-compose.https.yml \
  ps

curl -fsS https://grafana.restapp.site:8443/api/health
```

Si UFW está activo, habilitar solamente el nuevo puerto:

```bash
ufw allow 8443/tcp
ufw status
```

## Renovación

```bash
cd /opt/observabilidad-rest
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f docker-compose.https.yml \
  --profile ssl run --rm --entrypoint certbot certbot \
  renew --webroot --webroot-path=/var/www/certbot

docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f docker-compose.https.yml \
  exec nginx nginx -s reload
```
