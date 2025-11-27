defmodule WemachatDatabase.Repo.Migrations.RenameWhatsappToMpesaNumber do
  use Ecto.Migration

  def change do
    rename table(:users), :whatsapp_number, to: :mpesa_number
  end
end
