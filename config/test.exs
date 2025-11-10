import Config

# ========================================
# Database Configuration (Test)
# ========================================

# Configure the shared database repository for testing
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
config :wemachat_database, WemachatDatabase.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "wemachat_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# ========================================
# API Endpoint Configuration (Test)
# ========================================

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :wemachat_api, WemachatApiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "wemachat_test_secret_key_base_should_be_at_least_64_bytes_long_for_testing",
  server: false

# ========================================
# Logger Configuration (Test)
# ========================================

# Print only warnings and errors during test
config :logger, level: :warning

# ========================================
# Phoenix Configuration (Test)
# ========================================

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
