defmodule WemachatDatabase.Repo.Migrations.MakeChannelNamesCaseInsensitive do
  use Ecto.Migration

  def up do
    # Drop the existing case-sensitive unique index
    drop_if_exists unique_index(:channels, [:name])

    # Create a case-insensitive unique index using LOWER(name)
    # This prevents channels like "TechNews", "technews", "TECHNEWS" from coexisting
    create unique_index(:channels, ["lower(name)"], name: :channels_lower_name_index)
  end

  def down do
    # Reverse the migration
    drop_if_exists index(:channels, ["lower(name)"], name: :channels_lower_name_index)

    # Recreate the original case-sensitive unique index
    create unique_index(:channels, [:name])
  end
end
