defmodule WemachatDatabase.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix installed.

  This module provides robust migration handling with:
  - Proper app loading and starting
  - Retry logic for database connections
  - Better error reporting
  """

  @app :wemachat_database
  @max_retries 10
  @retry_delay 2_000

  require Logger

  @doc """
  Runs database migrations with retry logic.

  This is called by the Fly.io release_command in fly.toml
  """
  def migrate do
    Logger.info("Starting migration process...")

    # Load and start the application
    load_app()
    start_app()

    # Wait for database to be ready
    wait_for_database()

    # Run migrations for all repos
    for repo <- repos() do
      Logger.info("Running migrations for #{inspect(repo)}...")

      case run_migrations(repo) do
        {:ok, versions} ->
          Logger.info("Migrations completed successfully. Applied versions: #{inspect(versions)}")

        {:error, reason} ->
          Logger.error("Migration failed: #{inspect(reason)}")
          exit({:shutdown, 1})
      end
    end

    Logger.info("All migrations completed successfully!")
    :ok
  end

  @doc """
  Rolls back the database to a specific version.
  """
  def rollback(repo, version) do
    load_app()
    start_app()

    Logger.info("Rolling back #{inspect(repo)} to version #{version}...")

    case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version)) do
      {:ok, _, _} ->
        Logger.info("Rollback completed successfully")
        :ok

      {:error, reason} ->
        Logger.error("Rollback failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  # --------------------------------------------------
  # Private Functions
  # --------------------------------------------------

  defp repos do
    Application.get_env(@app, :ecto_repos, [WemachatDatabase.Repo])
  end

  defp load_app do
    Logger.info("Loading application #{@app}...")
    Application.load(@app)
  end

  defp start_app do
    Logger.info("Starting application #{@app}...")

    # Start the application and all dependencies
    case Application.ensure_all_started(@app) do
      {:ok, _started} ->
        Logger.info("Application started successfully")
        :ok

      {:error, reason} ->
        Logger.error("Failed to start application: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp wait_for_database(retry \\ 0) do
    if retry >= @max_retries do
      Logger.error("Database not available after #{@max_retries} retries")
      exit({:shutdown, 1})
    end

    repo = hd(repos())

    case repo.__adapter__().ensure_all_started(repo.config(), :temporary) do
      {:ok, _} ->
        Logger.info("Database connection established")
        :ok

      {:error, _reason} ->
        Logger.warning("Database not ready, retrying in #{@retry_delay}ms (attempt #{retry + 1}/#{@max_retries})...")
        Process.sleep(@retry_delay)
        wait_for_database(retry + 1)
    end
  end

  defp run_migrations(repo) do
    try do
      {:ok, versions, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
      {:ok, versions}
    rescue
      error ->
        {:error, error}
    catch
      :exit, reason ->
        {:error, reason}
    end
  end
end
