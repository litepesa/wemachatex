defmodule WemachatDatabase.Repo.Migrations.AddUserInfoToVideos do
  use Ecto.Migration

  def change do
    alter table(:videos) do
      add :user_name, :string
      add :user_image, :text
    end

    # Index for searching by user name
    create index(:videos, [:user_name])
  end
end
