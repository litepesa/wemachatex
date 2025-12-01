defmodule WemachatApiWeb.HealthController do
  use WemachatApiWeb, :controller

  def index(conn, _params) do
    # Optional: Add database health check
    case Ecto.Adapters.SQL.query(WemachatDatabase.Repo, "SELECT 1", []) do
      {:ok, _} ->
        json(conn, %{status: "ok", database: "connected"})
      {:error, _} ->
        conn
        |> put_status(503)
        |> json(%{status: "error", database: "disconnected"})
    end
  end
end
