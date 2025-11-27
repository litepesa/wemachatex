defmodule WemachatDatabase.Repo.Migrations.CreateCalls do
  use Ecto.Migration

  def change do
    # Calls table - tracks all voice/video calls between users
    create table(:calls, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :caller_id, references(:users, type: :string, on_delete: :delete_all), null: false
      add :callee_id, references(:users, type: :string, on_delete: :delete_all), null: false
      add :call_type, :string, null: false # "audio" or "video"
      add :status, :string, null: false, default: "pending" # "pending", "ringing", "active", "ended", "missed", "rejected", "cancelled"
      add :started_at, :utc_datetime
      add :ended_at, :utc_datetime
      add :duration_seconds, :integer, default: 0 # Total call duration in seconds
      add :is_deleted, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    # Indexes for performance
    create index(:calls, [:caller_id])
    create index(:calls, [:callee_id])
    create index(:calls, [:status])
    create index(:calls, [:inserted_at])
    create index(:calls, [:caller_id, :inserted_at])
    create index(:calls, [:callee_id, :inserted_at])

    # Check constraints
    create constraint(:calls, :call_type_valid, check: "call_type IN ('audio', 'video')")
    create constraint(:calls, :status_valid,
      check: "status IN ('pending', 'ringing', 'active', 'ended', 'missed', 'rejected', 'cancelled')")
    create constraint(:calls, :duration_non_negative, check: "duration_seconds >= 0")
    create constraint(:calls, :different_users, check: "caller_id != callee_id")
  end
end
