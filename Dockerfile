FROM oven/bun:latest

WORKDIR /workspace

COPY . .

RUN bun install

CMD ["bun", "run", "dev"]
