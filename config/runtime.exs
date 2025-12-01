import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

# ========================================
# Load .env file in development - IMPROVED VERSION
# ========================================
if config_env() == :dev do
  # Manual .env loader since Dotenv may not be available yet
  project_root = Path.expand("..", __DIR__)
  env_file = Path.join(project_root, ".env")

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
  else
    IO.puts("⚠ Warning: .env file not found at #{env_file}")
  end
end

# ========================================
# Database Configuration (ALL ENVIRONMENTS)
# Using PgAdmin format - individual connection params
# ========================================

# Get database configuration from environment
db_host = System.get_env("DB_HOST")
db_user = System.get_env("DB_USER")
db_password = System.get_env("DB_PASSWORD")
db_name = System.get_env("DB_NAME")
db_port = System.get_env("DB_PORT") || "5432"
db_pool_size = System.get_env("DB_POOL_SIZE") || "10"
db_ssl = System.get_env("DB_SSL") == "true"

# Debug output in dev
if config_env() == :dev do
  IO.puts("\n=== Database Configuration ===")
  IO.puts("DB_HOST: #{db_host}")
  IO.puts("DB_USER: #{db_user}")
  IO.puts("DB_NAME: #{db_name}")
  IO.puts("DB_PORT: #{db_port}")
  IO.puts("DB_SSL: #{db_ssl}")
  IO.puts("==============================\n")
end

# Build SSL configuration if enabled
ssl_config = if db_ssl do
  [
    verify: :verify_none,
    server_name_indication: :disable,
    versions: [:"tlsv1.2", :"tlsv1.3"]
  ]
else
  false
end

# Configure the database
config :wemachat_database, WemachatDatabase.Repo,
  username: db_user,
  password: db_password,
  hostname: db_host,
  port: String.to_integer(db_port),
  database: db_name,
  pool_size: String.to_integer(db_pool_size),
  ssl: ssl_config,
  migration_primary_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime],
  stacktrace: config_env() == :dev,
  show_sensitive_data_on_connection_error: config_env() == :dev

# ========================================
# Firebase Configuration
# ========================================
config :wemachat_api, :firebase,
  project_id: System.get_env("FIREBASE_PROJECT_ID"),
  credentials_path: System.get_env("FIREBASE_CREDENTIALS_PATH") || "priv/texgb-50a98-firebase-adminsdk-fbsvc-a19675f920.json"

# ========================================
# Cloudflare R2 Configuration
# ========================================
config :ex_aws,
  access_key_id: System.get_env("R2_ACCESS_KEY"),
  secret_access_key: System.get_env("R2_SECRET_KEY"),
  region: "auto",
  json_codec: Jason

config :ex_aws, :s3,
  scheme: "https://",
  host: "#{System.get_env("R2_ACCOUNT_ID")}.r2.cloudflarestorage.com",
  region: "auto"

config :wemachat_api, :r2,
  account_id: System.get_env("R2_ACCOUNT_ID"),
  bucket_name: System.get_env("R2_BUCKET_NAME") || "weibaomedia",
  public_url: System.get_env("R2_PUBLIC_URL") || "https://pub-5e8ab62547db4f58851382161d280c19.r2.dev"

# ========================================
# M-Pesa Payment Configuration
# ========================================
config :wemachat_core, :mpesa,
  # Environment: "sandbox" or "production"
  environment: System.get_env("MPESA_ENVIRONMENT") || "sandbox",
  # Safaricom Daraja API credentials (from Daraja Portal)
  consumer_key: System.get_env("MPESA_CONSUMER_KEY"),
  consumer_secret: System.get_env("MPESA_CONSUMER_SECRET"),
  # Business shortcode (Paybill or Till Number)
  business_shortcode: System.get_env("MPESA_SHORTCODE") || "174379",
  # Lipa Na M-Pesa Online Passkey (from Daraja Portal)
  passkey: System.get_env("MPESA_PASSKEY"),
  # Callback URL for M-Pesa to send payment results
  # Must be publicly accessible (use ngrok for local testing)
  callback_url: System.get_env("MPESA_CALLBACK_URL") || "http://localhost:4000/api/v1/payment/callback"

# ========================================
# PHX_SERVER Control
# ========================================

# Enable server if PHX_SERVER=true environment variable is set
if System.get_env("PHX_SERVER") do
  config :wemachat_api, WemachatApiWeb.Endpoint, server: true
end

# ========================================
# Production Configuration
# ========================================

if config_env() == :prod do
  # In production, you can optionally override with DATABASE_URL if needed
  # But the individual params above will work fine too

  # ========================================
  # Secret Key Base
  # ========================================

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # ========================================
  # Phoenix Endpoint Configuration
  # ========================================

  host = System.get_env("PHX_HOST") || "api.wemachat.co.ke"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :wemachat_api, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :wemachat_api, WemachatApiWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
end
