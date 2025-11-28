import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

# ========================================
# Load .env file in development
# ========================================
if config_env() == :dev do
  try do
    Dotenv.load()
  rescue
    _ -> :ok
  end
end

# ========================================
# Database Configuration - FOOLPROOF METHOD
# ========================================
# Use the built-in Ecto.Repo.Supervisor.init/2 which handles DATABASE_URL automatically
# This is the standard way Ecto handles database URLs in production

database_url = System.get_env("DATABASE_URL")

cond do
  database_url ->
    # Production: Use DATABASE_URL directly - Ecto handles parsing internally
    config :wemachat_database, WemachatDatabase.Repo,
      url: database_url,
      ssl: true,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
      queue_target: 5000,
      queue_interval: 1000

  config_env() == :dev ->
    # Development: Use individual environment variables
    config :wemachat_database, WemachatDatabase.Repo,
      username: System.get_env("DB_USER") || "postgres",
      password: System.get_env("DB_PASSWORD") || "postgres",
      hostname: System.get_env("DB_HOST") || "localhost",
      port: String.to_integer(System.get_env("DB_PORT") || "5432"),
      database: System.get_env("DB_NAME") || "wemachat_dev",
      ssl: false,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "3")

  true ->
    raise "DATABASE_URL environment variable is required in production"
end

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
  environment: System.get_env("MPESA_ENVIRONMENT") || "sandbox",
  consumer_key: System.get_env("MPESA_CONSUMER_KEY"),
  consumer_secret: System.get_env("MPESA_CONSUMER_SECRET"),
  business_shortcode: System.get_env("MPESA_SHORTCODE") || "174379",
  passkey: System.get_env("MPESA_PASSKEY"),
  callback_url: System.get_env("MPESA_CALLBACK_URL") || "http://localhost:4000/api/v1/payment/callback"

# ========================================
# PHX_SERVER Control
# ========================================
if System.get_env("PHX_SERVER") do
  config :wemachat_api, WemachatApiWeb.Endpoint, server: true
end

# ========================================
# Production Configuration
# ========================================
if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "wemachatex.fly.dev"
  port = String.to_integer(System.get_env("PORT") || "8080")

  config :wemachat_api, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :wemachat_api, WemachatApiWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end
