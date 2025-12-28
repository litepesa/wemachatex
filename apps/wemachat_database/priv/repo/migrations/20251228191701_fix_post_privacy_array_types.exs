defmodule WemachatDatabase.Repo.Migrations.FixPostPrivacyArrayTypes do
  use Ecto.Migration

  def up do
    # Change visible_to and hidden_from from uuid[] to text[] to support Firebase UID strings
    execute "ALTER TABLE posts ALTER COLUMN visible_to TYPE text[] USING visible_to::text[]"
    execute "ALTER TABLE posts ALTER COLUMN hidden_from TYPE text[] USING hidden_from::text[]"
  end

  def down do
    # Rollback: convert back to uuid[] (only safe if all values are valid UUIDs)
    execute "ALTER TABLE posts ALTER COLUMN visible_to TYPE uuid[] USING visible_to::uuid[]"
    execute "ALTER TABLE posts ALTER COLUMN hidden_from TYPE uuid[] USING hidden_from::uuid[]"
  end
end
