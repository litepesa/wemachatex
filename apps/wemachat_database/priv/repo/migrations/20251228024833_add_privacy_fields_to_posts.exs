defmodule WemachatDatabase.Repo.Migrations.AddPrivacyFieldsToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :visible_to, {:array, :binary_id}, default: []
      add :hidden_from, {:array, :binary_id}, default: []
      add :location, :string
    end

    # Add GIN indexes for efficient privacy array queries
    create index(:posts, [:visible_to], using: :gin)
    create index(:posts, [:hidden_from], using: :gin)
    create index(:posts, [:location])
  end
end
