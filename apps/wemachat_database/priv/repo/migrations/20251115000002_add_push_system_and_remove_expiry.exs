defmodule WemachatDatabase.Repo.Migrations.AddPushSystemAndRemoveExpiry do
  use Ecto.Migration

  def up do
    # Add push notification fields to videos
    alter table(:videos) do
      # Silent push fields (no user notification, just feed influence)
      add :push_to_all, :boolean, default: false, null: false
      add :push_to_counties, {:array, :string}
      add :push_to_constituencies, {:array, :string}
      add :push_to_wards, {:array, :string}
      add :pushed_at, :utc_datetime_usec  # When admin activated push
    end

    # Add indexes for push queries
    create index(:videos, [:push_to_all])
    create index(:videos, [:pushed_at])
    create index(:videos, [:push_to_counties])

    # Note: We're keeping expires_at field for backward compatibility
    # but it will no longer be enforced in queries
    # Videos now stay on the platform forever
  end

  def down do
    # Remove push indexes
    drop index(:videos, [:push_to_all])
    drop index(:videos, [:pushed_at])
    drop index(:videos, [:push_to_counties])

    # Remove push fields
    alter table(:videos) do
      remove :push_to_all
      remove :push_to_counties
      remove :push_to_constituencies
      remove :push_to_wards
      remove :pushed_at
    end
  end
end
