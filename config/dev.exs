import Config

# ========================================
# Load Environment Variables from .env
# ========================================
# Load .env file in development to automatically set environment variables
# Get the project root directory (one level up from config/)
project_root = Path.expand("..", __DIR__)
env_file = Path.join(project_root, ".env")

# Simple .env file parser for config time (before dependencies are loaded)
if File.exists?(env_file) do
  env_file
  |> File.read!()
  |> String.split("\n")
  |> Enum.each(fn line ->
    line = String.trim(line)
    # Skip empty lines and comments
    unless line == "" or String.starts_with?(line, "#") do
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          # Remove quotes if present
          value = String.trim(value)
          value = if String.starts_with?(value, "\"") and String.ends_with?(value, "\"") do
            String.slice(value, 1..-2//1)
          else
            value
          end
          System.put_env(key, value)
        _ -> :ok
      end
    end
  end)
  IO.puts("✓ Loaded environment variables from .env")
end

# ========================================
# Database Configuration (Development)
# ========================================

# Configure the shared database repository
# IMPORTANT: Load .env file or set environment variables before running
config :wemachat_database, WemachatDatabase.Repo,
  username: System.get_env("DB_USER") || "postgres",
  password: System.get_env("DB_PASSWORD") || "postgres",
  hostname: System.get_env("DB_HOST") || "localhost",
  database: System.get_env("DB_NAME") || "wemachat_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: String.to_integer(System.get_env("DB_POOL_SIZE") || "3"),
  port: String.to_integer(System.get_env("DB_PORT") || "5432"),
  ssl: [
    verify: :verify_none,  # This bypasses certificate verification
    server_name_indication: :disable
  ]

# ========================================
# API Endpoint Configuration (Development)
# ========================================

# For development, we disable any cache and enable
# debugging and code reloading.
config :wemachat_api, WemachatApiWeb.Endpoint,
  # Binding to all network interfaces to allow access from Flutter app on external devices
  # Changed from {127, 0, 0, 1} to {0, 0, 0, 0} for development access
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: System.get_env("SECRET_KEY_BASE") || "wemachat_dev_secret_key_base_should_be_at_least_64_bytes_long_for_security",
  watchers: []

# Enable dev routes for dashboard and mailbox
config :wemachat_api, dev_routes: false

# ========================================
# Logger Configuration (Development)
# ========================================

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# ========================================
# Phoenix Configuration (Development)
# ========================================

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Disable Swoosh API client as it is only required for production adapters.
# config :swoosh, :api_client, false
