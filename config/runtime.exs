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
  # ========================================
  # Database Configuration
  # ========================================

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: postgresql://USER:PASS@HOST:PORT/DATABASE
      """

  # Parse the DATABASE_URL into individual components
  # Format: postgresql://user:password@host:port/database
  # Gigalixir provides DATABASE_URL automatically
  %{
    userinfo: userinfo,
    host: host,
    port: port,
    path: "/" <> database
  } = URI.parse(database_url)

  [username, password] = String.split(userinfo, ":")

  config :wemachat_database, WemachatDatabase.Repo,
    username: username,
    password: password,
    database: database,
    hostname: host,
    port: port || 5432,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2"),
    ssl: true,
    ssl_opts: [
      verify: :verify_none,  # IMPORTANT: Add this for Gigalixir
      server_name_indication: :disable,
      cacertfile: "/etc/ssl/certs/ca-certificates.crt"
    ]

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

  # Gigalixir provides APP_NAME environment variable
  app_name = System.get_env("APP_NAME") || "wemachatex"
  host = System.get_env("PHX_HOST") || "#{app_name}.gigalixirapp.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :wemachat_api, WemachatApiWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0},
      port: port
      # Removed transport_options from here
      # transport_options: [socket_opts: [:inet6]]
    ],
    secret_key_base: secret_key_base,
    server: true,
    cache_static_manifest: "priv/static/cache_manifest.json"

  # Ensure no transport_options at top level (override any from other configs)
  config :wemachat_api, WemachatApiWeb.Endpoint,
    transport_options: nil
end
