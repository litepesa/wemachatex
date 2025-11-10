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
# Database Configuration (Non-Dev Environments Only)
# ========================================
# In dev mode, we use the hardcoded config in dev.exs
# In prod/test, we use environment variables
if config_env() != :dev do
  config :wemachat_database, WemachatDatabase.Repo,
    username: System.get_env("DB_USER") || "postgres",
    password: System.get_env("DB_PASSWORD") || "postgres",
    hostname: System.get_env("DB_HOST") || "localhost",
    port: String.to_integer(System.get_env("DB_PORT") || "5432"),
    database: System.get_env("DB_NAME") || "wemadb",
    ssl: System.get_env("DB_SSL") == "true",
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
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
  # ========================================
  # Database Configuration
  # ========================================

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :wemachat_database, WemachatDatabase.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "100"),
    socket_options: maybe_ipv6

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

  # ========================================
  # SSL Configuration (Optional)
  # ========================================

  # To enable SSL:
  #
  #     config :wemachat_api, WemachatApiWeb.Endpoint,
  #       https: [
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SSL_KEY_PATH"),
  #         certfile: System.get_env("SSL_CERT_PATH")
  #       ]
  #
  # For force_ssl configuration:
  #
  #     config :wemachat_api, WemachatApiWeb.Endpoint,
  #       force_ssl: [hsts: true]
end
