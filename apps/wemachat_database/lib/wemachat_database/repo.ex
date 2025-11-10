defmodule WemachatDatabase.Repo do
  use Ecto.Repo,
    otp_app: :wemachat_database,
    adapter: Ecto.Adapters.Postgres
end
