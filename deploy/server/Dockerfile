# The Deadnight game server: headless Godot running `NightHost` (game/net/night_host.gd) on a WebSocket.
# Build context: a folder with this Dockerfile, railway.toml and the `game/` project at game/ (deploy.sh assembles it).
# Run locally:  docker run --rm -e PORT=8910 -p 8910:8910 deadnight-server
# Railway sets $PORT; its edge terminates TLS (wss://), so the server speaks plain ws:// inside.
FROM debian:bookworm-slim AS godot

# The Godot version and SHA-512 are the ones pinned in the GDStudio kit's tools.toml (linux-x64).
ARG GODOT_VERSION=4.7.2
ARG GODOT_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/godot.zip \
        "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && echo "${GODOT_SHA512}  /tmp/godot.zip" | sha512sum -c - \
    && unzip -q /tmp/godot.zip -d /opt \
    && mv "/opt/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /opt/godot

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 game
COPY --from=godot /opt/godot /usr/local/bin/godot
# /app must belong to the game user: Godot writes its import cache (.godot/) inside the project folder.
RUN mkdir /app && chown game:game /app
WORKDIR /app
USER game
COPY --chown=game:game game /app
# Import once at build time so the container starts without a first-run import.
RUN godot --headless --path /app --import
ENV PORT=8910
EXPOSE 8910
CMD ["godot", "--headless", "--path", "/app", "--", "--server"]
