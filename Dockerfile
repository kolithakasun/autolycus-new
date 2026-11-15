FROM node:19.8.1-slim AS ui

WORKDIR /ui
COPY ui/package.json ui/yarn.lock ./
RUN yarn install --frozen-lockfile
COPY ui/ ./
ENV API_PREFIX=/api
ENV NEXT_TELEMETRY_DISABLED=1
RUN yarn build

FROM python:3.9-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    API_DEBUG=False \
    NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        nginx \
        nodejs \
        ffmpeg \
        gcc \
        g++ \
        libffi-dev \
        libxml2-dev \
        libxslt1-dev \
        rsync \
        handbrake-cli \
        aria2 \
        p7zip-full \
        curl \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/nginx/sites-enabled/default

WORKDIR /app

COPY api/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY api/ /app
COPY --from=ui /ui/.next /ui/.next
COPY --from=ui /ui/public /ui/public
COPY --from=ui /ui/node_modules /ui/node_modules
COPY --from=ui /ui/package.json /ui/package.json
COPY --from=ui /ui/next.config.js /ui/next.config.js
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY docker/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh \
    && mkdir -p /downloads /app/logs

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
