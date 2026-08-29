FROM node:22-alpine AS dependencies
WORKDIR /app
ARG NPM_REGISTRY=https://registry.npmmirror.com
RUN npm install -g pnpm@10.15.1 --registry=${NPM_REGISTRY} \
    && pnpm config set registry ${NPM_REGISTRY}
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

FROM node:22-alpine AS build
WORKDIR /app
ARG NPM_REGISTRY=https://registry.npmmirror.com
RUN npm install -g pnpm@10.15.1 --registry=${NPM_REGISTRY} \
    && pnpm config set registry ${NPM_REGISTRY}
COPY --from=dependencies /app/node_modules ./node_modules
COPY . .
RUN pnpm build

FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 nextjs
COPY --from=build /app/public ./public
COPY --from=build --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=build --chown=nextjs:nodejs /app/.next/static ./.next/static
USER nextjs
EXPOSE 3000
CMD ["node", "server.js"]

