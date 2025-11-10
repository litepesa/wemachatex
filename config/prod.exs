import Config

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
