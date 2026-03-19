FROM oven/bun:1 AS build
WORKDIR /app
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile
COPY . .

FROM oven/bun:1-slim
WORKDIR /app
COPY --from=build /app .
EXPOSE 3030
CMD ["bun", "run", "server.ts"]
