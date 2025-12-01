import Config

# ========================================
# Production Configuration
# ========================================

# For production, don't forget to configure the url host
# to something meaningful, Phoenix uses this information
# when generating URLs.

config :wemachat_api, WemachatApiWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true

# ========================================
# Logger Configuration (Production)
# ========================================

# Do not print debug messages in production
config :logger, level: :info

# ========================================
# Runtime Configuration
# ========================================

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
