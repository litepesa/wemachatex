# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.

import Config

# ========================================
# Database Configuration (wemachat_database)
# ========================================

config :wemachat_database,
  ecto_repos: [WemachatDatabase.Repo]

# Configure the shared database repository
config :wemachat_database, WemachatDatabase.Repo,
  migration_primary_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime]

# ========================================
# API Configuration (wemachat_api)
# ========================================

config :wemachat_api,
  ecto_repos: [WemachatDatabase.Repo],  # Use shared database repo
  generators: [timestamp_type: :utc_datetime]

# Configure the Phoenix endpoint
config :wemachat_api, WemachatApiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: WemachatApiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Wemachat.PubSub,
  live_view: [signing_salt: "WemaChat2025"]

# ========================================
# Logger Configuration
# ========================================

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id]

# ========================================
# JSON Library
# ========================================

config :phoenix, :json_library, Jason

# ========================================
# Environment Specific Config
# ========================================

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
