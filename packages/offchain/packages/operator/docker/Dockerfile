# syntax=docker/dockerfile:1

# Build stage - builds the monorepo workspace
FROM node:24-alpine AS builder

WORKDIR /app

# Copy root package files for workspace
COPY package*.json ./
COPY tsconfig.json ./
COPY packages/operator/package*.json ./packages/operator/
COPY packages/shared/package*.json ./packages/shared/
COPY packages/coordinator/package*.json ./packages/coordinator/
COPY packages/operator-cli/package*.json ./packages/operator-cli/

# Install all dependencies (workspace-aware)
RUN npm ci --ignore-scripts --workspace=@reineira-ops/operator --workspace=@reineira-ops/shared

# Copy source code
COPY packages/shared ./packages/shared
COPY packages/operator ./packages/operator

# Build shared first, then operator
RUN npm run build --workspace=@reineira-ops/shared
RUN npm run build --workspace=@reineira-ops/operator

# Production stage
FROM node:24-alpine AS production

RUN apk add --no-cache dumb-init wget

WORKDIR /app

RUN addgroup -g 1001 -S nodejs && \
    adduser -S nestjs -u 1001

ENV NODE_ENV=production

# Copy package files
COPY package*.json ./
COPY packages/operator/package*.json ./packages/operator/
COPY packages/shared/package*.json ./packages/shared/
COPY packages/coordinator/package*.json ./packages/coordinator/
COPY packages/operator-cli/package*.json ./packages/operator-cli/

# Install production dependencies only
RUN npm ci --ignore-scripts --omit=dev --workspace=@reineira-ops/operator --workspace=@reineira-ops/shared && \
    npm cache clean --force

# Copy built artifacts
COPY --from=builder --chown=nestjs:nodejs /app/packages/shared/dist ./packages/shared/dist
COPY --from=builder --chown=nestjs:nodejs /app/packages/operator/dist ./packages/operator/dist

USER nestjs

EXPOSE 3002

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3002/status || exit 1

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "packages/operator/dist/main.js"]
