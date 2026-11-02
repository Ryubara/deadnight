# Serves the exported Deadnight web build. Build context: a folder with this Dockerfile, the Caddyfile, railway.toml
# the discord-bridge.js source and the export at build/web (CI assembles it: .github/workflows/ci.yml, job `deploy`;
# locally see the web-export page).
# The Discord Embedded App SDK (MIT) and esbuild, bundled with our bridge at image build time: the SDK is not in the
# repository, and a page outside Discord never loads the result.
FROM node:24-alpine AS discord
WORKDIR /bridge
RUN npm install --no-save --no-audit --no-fund @discord/embedded-app-sdk@2.5.0 esbuild@0.28.2
COPY discord-bridge.js .
RUN npx esbuild discord-bridge.js --bundle --format=esm --target=es2022 --minify --outfile=discord-bridge.out.js

FROM alpine:3.22 AS compress
RUN apk add --no-cache brotli
COPY build/web /srv
COPY --from=discord /bridge/discord-bridge.out.js /srv/discord-bridge.js
# The large files, compressed once at build time: gzip for any client, brotli for browsers (about a quarter smaller).
RUN cd /srv && find . -type f \( -name '*.wasm' -o -name '*.pck' -o -name '*.js' -o -name '*.html' \) \
        -exec sh -c 'gzip -9 -k "$1" && brotli -q 9 -k "$1"' _ {} \;

FROM caddy:2.11.7-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=compress /srv /srv
ENV PORT=8080
EXPOSE 8080
