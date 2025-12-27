defmodule WemachatDatabase.Repo.Migrations.RemoveVideoExpiresAt do
  use Ecto.Migration

  def change do
    alter table(:videos) do
      remove :expires_at
    end
  end
end
