defmodule WemachatCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Background job to cleanup expired statuses (runs every hour)
      WemachatCore.Jobs.StatusCleanup
      # Note: VideoCleanup job removed - videos no longer expire
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WemachatCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
