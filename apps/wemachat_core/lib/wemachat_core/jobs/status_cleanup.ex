defmodule WemachatCore.Jobs.StatusCleanup do
  @moduledoc """
  Background job that periodically deletes expired statuses.
  Runs every hour to clean up statuses where expires_at <= NOW().
  """
  use GenServer
  require Logger

  alias WemachatCore.Contexts.Statuses

  # Run cleanup every hour (3600000 milliseconds)
  @cleanup_interval :timer.hours(1)

  ## Client API

  @doc """
  Starts the status cleanup GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually trigger cleanup (useful for testing).
  """
  def cleanup_now do
    GenServer.call(__MODULE__, :cleanup_now)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Schedule first cleanup after 1 minute (give server time to fully start)
    schedule_cleanup(:timer.minutes(1))
    Logger.info("StatusCleanup job started. Will run every hour.")
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    perform_cleanup()
    schedule_cleanup(@cleanup_interval)
    {:noreply, state}
  end

  @impl true
  def handle_call(:cleanup_now, _from, state) do
    result = perform_cleanup()
    {:reply, result, state}
  end

  ## Private Functions

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end

  defp perform_cleanup do
    Logger.info("Starting expired status cleanup...")

    case Statuses.cleanup_expired() do
      {:ok, count} ->
        if count > 0 do
          Logger.info("Deleted #{count} expired statuses")
        else
          Logger.debug("No expired statuses to delete")
        end

        {:ok, count}

      {:error, reason} ->
        Logger.error("Failed to delete expired statuses: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
