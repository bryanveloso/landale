# Install dependencies only when needed.
FROM node:14 AS deps
RUN npm install -g pnpm
WORKDIR /app
COPY pnpm-lock.yaml ./
RUN pnpm fetch

# Rebuild source code only when needed.
FROM node:14 AS builder
RUN npm install -g pnpm
WORKDIR /app
COPY /renderer/ .
COPY --from=deps /app/node_modules ./node_modules
RUN pnpm install -r --offline
RUN pnpm build

# Production image, copy all the files and run `next`.
FROM node:14 AS runner
WORKDIR /app

ENV NODE_ENV production

COPY --from=builder /app/next.config.js ./
# COPY --from=builder /app/public ./public
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json

EXPOSE 3000

ENV PORT 3000

CMD ["node_modules/.bin/next", "start"]
