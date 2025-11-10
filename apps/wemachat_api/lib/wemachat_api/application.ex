defmodule WemachatApi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Load Firebase credentials for Goth
    firebase_config = Application.get_env(:wemachat_api, :firebase)
    credentials_filename = firebase_config[:credentials_path]

    # Get the absolute path to the file in the priv directory
    credentials_path = Application.app_dir(:wemachat_api, Path.join("priv", Path.basename(credentials_filename)))

    # Read the service account JSON file
    credentials_json = File.read!(credentials_path) |> Jason.decode!()

    children = [
      WemachatApiWeb.Telemetry,
      {Goth, name: WemachatApi.Goth, source: {:service_account, credentials_json, []}},
      # Note: WemachatDatabase.Repo is started by wemachat_database app
      {DNSCluster, query: Application.get_env(:wemachat_api, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Wemachat.PubSub},
      # Start a worker by calling: WemachatApi.Worker.start_link(arg)
      # {WemachatApi.Worker, arg},
      # Start to serve requests, typically the last entry
      WemachatApiWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WemachatApi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WemachatApiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
