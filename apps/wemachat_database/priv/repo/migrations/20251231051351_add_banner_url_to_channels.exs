defmodule WemachatDatabase.Repo.Migrations.AddBannerUrlToChannels do
  use Ecto.Migration

  def change do
    alter table(:channels) do
      add :banner_url, :string
    end
  end
end
