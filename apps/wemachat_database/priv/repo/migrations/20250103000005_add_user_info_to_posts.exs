defmodule WemachatDatabase.Repo.Migrations.AddUserInfoToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :user_name, :string
      add :user_image, :text
    end

    # Index for searching by user name
    create index(:posts, [:user_name])
  end
end
