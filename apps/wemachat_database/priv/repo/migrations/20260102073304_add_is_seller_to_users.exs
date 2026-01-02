defmodule WemachatDatabase.Repo.Migrations.AddIsSellerToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_seller, :boolean, default: false, null: false
    end
  end
end
