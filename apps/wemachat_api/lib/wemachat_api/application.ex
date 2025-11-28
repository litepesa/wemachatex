defmodule WemachatApi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Load Firebase credentials from environment variable or file
    credentials_json =
      case System.get_env("FIREBASE_CREDENTIALS_JSON") do
        nil ->
          # Fall back to file in development
          firebase_config = Application.get_env(:wemachat_api, :firebase)
          credentials_path = firebase_config[:credentials_path]

          if credentials_path && File.exists?(credentials_path) do
            try do
              File.read!(credentials_path) |> Jason.decode!()
            rescue
              e ->
                Logger.error("Failed to read Firebase credentials from #{credentials_path}: #{inspect(e)}")
                nil
            end
          else
            Logger.warning("Firebase credentials path not found or not set")
            nil
          end

        json_string ->
          try do
            # First try to decode as base64 (from Fly.io secret)
            case Base.decode64(json_string) do
              {:ok, decoded} ->
                Jason.decode!(decoded)
              :error ->
                # If base64 fails, try direct JSON parsing (for development)
                Jason.decode!(json_string)
            end
          rescue
            e ->
              Logger.error("Failed to parse FIREBASE_CREDENTIALS_JSON: #{inspect(e)}")
              nil
          end
      end

    # Build children based on whether Firebase is available
    children =
      if credentials_json do
        Logger.info("Firebase credentials loaded successfully")

        [
          WemachatApiWeb.Telemetry,
          {Goth, name: WemachatApi.Goth, source: {:service_account, credentials_json, []}},
          {DNSCluster, query: Application.get_env(:wemachat_api, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: Wemachat.PubSub},
          WemachatApiWeb.Endpoint
        ]
      else
        Logger.warning("Starting without Firebase - some features may not work")

        [
          WemachatApiWeb.Telemetry,
          {DNSCluster, query: Application.get_env(:wemachat_api, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: Wemachat.PubSub},
          WemachatApiWeb.Endpoint
        ]
      end

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
