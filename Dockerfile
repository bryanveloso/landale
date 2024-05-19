FROM oven/bun:latest

WORKDIR /workspace

COPY . .

RUN bun install

# We have to run `bun install` a second time because of the following:
# https://github.com/vitejs/vite/discussions/15532#discussioncomment-8141236
RUN bun install

CMD ["bun", "run", "dev"]
