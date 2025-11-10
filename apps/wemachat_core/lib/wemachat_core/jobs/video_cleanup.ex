defmodule WemachatCore.Jobs.VideoCleanup do
  @moduledoc """
  Background job that periodically deletes expired videos.
  Runs every hour to clean up videos where expires_at <= NOW().
  """
  use GenServer
  require Logger

  alias WemachatCore.Contexts.Videos

  # Run cleanup every hour (3600000 milliseconds)
  @cleanup_interval :timer.hours(1)

  ## Client API

  @doc """
  Starts the video cleanup GenServer.
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
    Logger.info("VideoCleanup job started. Will run every hour.")
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
    Logger.info("Starting expired video cleanup...")

    case Videos.delete_expired_videos() do
      {:ok, count} ->
        if count > 0 do
          Logger.info("Deleted #{count} expired videos")
        else
          Logger.debug("No expired videos to delete")
        end

        {:ok, count}

      {:error, reason} ->
        Logger.error("Failed to delete expired videos: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
