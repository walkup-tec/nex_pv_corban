# Imagem da VPS (EasyPanel). O build da Lovable ignora NITRO_PRESET e continua no Cloudflare.
FROM oven/bun:1.4.2 AS build
WORKDIR /app

COPY package.json bun.lock bunfig.toml ./
RUN bun install --frozen-lockfile

COPY . .

ENV NITRO_PRESET=node-server
RUN bun run build

FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    NITRO_HOST=0.0.0.0 \
    PORT=30322
COPY --from=build /app/.output ./.output
COPY docker-entrypoint.mjs /app/docker-entrypoint.mjs
EXPOSE 30322
CMD ["node", "--import", "./docker-entrypoint.mjs", ".output/server/index.mjs"]
