# syntax=docker/dockerfile:1

# Build stage - builds the monorepo workspace
FROM node:24-alpine AS builder

WORKDIR /app

# Copy root package files for workspace
COPY package*.json ./
COPY tsconfig.json ./
COPY packages/coordinator/package*.json ./packages/coordinator/
COPY packages/shared/package*.json ./packages/shared/
COPY packages/operator/package*.json ./packages/operator/
COPY packages/operator-cli/package*.json ./packages/operator-cli/

# Install all dependencies (workspace-aware)
RUN npm ci --ignore-scripts --workspace=@reineira-ops/coordinator --workspace=@reineira-ops/shared

# Copy source code
COPY packages/shared ./packages/shared
COPY packages/coordinator ./packages/coordinator

# Build shared first, then coordinator
RUN npm run build --workspace=@reineira-ops/shared
RUN npm run build --workspace=@reineira-ops/coordinator

# Production stage
FROM node:24-alpine AS production

RUN apk add --no-cache dumb-init wget

WORKDIR /app

RUN addgroup -g 1001 -S nodejs && \
    adduser -S nestjs -u 1001

ENV NODE_ENV=production

# Copy package files
COPY package*.json ./
COPY packages/coordinator/package*.json ./packages/coordinator/
COPY packages/shared/package*.json ./packages/shared/
COPY packages/operator/package*.json ./packages/operator/
COPY packages/operator-cli/package*.json ./packages/operator-cli/

# Install production dependencies only
RUN npm ci --ignore-scripts --omit=dev --workspace=@reineira-ops/coordinator --workspace=@reineira-ops/shared && \
    npm cache clean --force

# Copy built artifacts
COPY --from=builder --chown=nestjs:nodejs /app/packages/shared/dist ./packages/shared/dist
COPY --from=builder --chown=nestjs:nodejs /app/packages/coordinator/dist ./packages/coordinator/dist

USER nestjs

EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3001/operators/stats || exit 1

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "packages/coordinator/dist/main.js"]
