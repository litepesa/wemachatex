defmodule WemachatDatabase.Repo.Migrations.AddUserInfoToWallets do
  use Ecto.Migration

  def change do
    alter table(:wallets) do
      add :username, :string
      add :phone_number, :string
      add :mpesa_number, :string
    end
  end
end
