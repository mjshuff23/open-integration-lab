FROM node:22.22.2-bookworm-slim AS base

WORKDIR /app

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN corepack enable

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/*

FROM base AS build

COPY package.json pnpm-lock.yaml ./

RUN corepack prepare pnpm@10.14.0 --activate \
    && pnpm install --frozen-lockfile

COPY . .

RUN pnpm prisma:generate \
    && pnpm build \
    && pnpm prune --prod

FROM base AS runner

ENV NODE_ENV=production
ENV PORT=4000

COPY --from=build /app/package.json ./package.json
COPY --from=build /app/pnpm-lock.yaml ./pnpm-lock.yaml
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/prisma ./prisma

EXPOSE 4000

CMD ["pnpm", "start:prod"]
