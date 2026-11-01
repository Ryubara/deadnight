# Serves the exported Deadnight web build. Build context: a folder with this Dockerfile, the Caddyfile, railway.toml
# and the export at build/web (CI assembles it: .github/workflows/ci.yml, job `deploy`; locally see the web-export page).
FROM alpine:3.22 AS compress
RUN apk add --no-cache brotli
COPY build/web /srv
# The large files, compressed once at build time: gzip for any client, brotli for browsers (about a quarter smaller).
RUN cd /srv && find . -type f \( -name '*.wasm' -o -name '*.pck' -o -name '*.js' -o -name '*.html' \) \
        -exec sh -c 'gzip -9 -k "$1" && brotli -q 9 -k "$1"' _ {} \;

FROM caddy:2.11.7-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=compress /srv /srv
ENV PORT=8080
EXPOSE 8080
