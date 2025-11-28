# Builder stage
FROM elixir:1.16.0-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache build-base git

# Set environment
ENV MIX_ENV=prod

# Copy mix files
COPY mix.exs mix.lock ./
COPY apps apps

# Get dependencies
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod

# Compile dependencies
RUN mix deps.compile

# Compile application
RUN mix compile

# Build assets (if exists)
RUN if [ -d "apps/wemachat_api/assets" ] && [ -f "apps/wemachat_api/assets/package.json" ]; then \
      apk add --no-cache nodejs npm && \
      cd apps/wemachat_api/assets && \
      npm install && npm run deploy && \
      cd /app; \
    fi

# Create release
RUN mix release wemachatex

# Runtime stage
FROM elixir:1.16.0-alpine

WORKDIR /app

# Install runtime dependencies only (no build tools)
RUN apk add --no-cache libssl3 ncurses-libs ca-certificates

# Copy entire release directory
COPY --from=builder /app/_build/prod/rel/wemachatex /app/wemachatex

# Create non-root user
RUN addgroup -g 1000 app && \
    adduser -u 1000 -G app -s /bin/sh -D app && \
    chown -R app:app /app

USER app

ENV HOME=/app

EXPOSE 8080

CMD ["/app/wemachatex/bin/wemachatex", "start"]