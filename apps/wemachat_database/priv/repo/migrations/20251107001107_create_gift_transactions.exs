defmodule WemachatDatabase.Repo.Migrations.CreateGiftTransactions do
  use Ecto.Migration

  def change do
    create table(:gift_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :gift_id, :string, null: false
      add :gift_name, :string, null: false
      add :gift_emoji, :string
      add :gift_rarity, :string
      add :price, :integer, null: false
      add :recipient_amount, :integer, null: false
      add :platform_commission, :integer, null: false
      add :context, :string, null: false
      add :context_id, :string
      add :message, :text
      add :sender_id, :string, null: false
      add :recipient_id, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # Indexes for efficient querying
    create index(:gift_transactions, [:sender_id])
    create index(:gift_transactions, [:recipient_id])
    create index(:gift_transactions, [:context, :context_id])
    create index(:gift_transactions, [:inserted_at])
  end
end
