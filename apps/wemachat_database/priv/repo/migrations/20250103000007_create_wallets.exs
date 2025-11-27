defmodule WemachatDatabase.Repo.Migrations.CreateWallets do
  use Ecto.Migration

  def change do
    # Wallets table - Virtual coin wallet (one per user)
    create table(:wallets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :string, on_delete: :delete_all), null: false

      # Balance and statistics
      add :balance, :integer, default: 0, null: false
      add :total_earned, :integer, default: 0, null: false
      add :total_spent, :integer, default: 0, null: false

      # Lifecycle
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    # One wallet per user
    create unique_index(:wallets, [:user_id])
    create index(:wallets, [:is_active])

    # Check constraint - balance cannot be negative
    create constraint(:wallets, :balance_non_negative,
             check: "balance >= 0"
           )

    # Transactions table - History of all wallet transactions
    create table(:transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :wallet_id, references(:wallets, type: :binary_id, on_delete: :delete_all), null: false

      # Transaction details
      add :transaction_type, :string, null: false
      # Types: "earn", "spend", "gift_sent", "gift_received", "purchase", "refund", "admin_credit", "admin_debit"

      add :amount, :integer, null: false
      add :balance_before, :integer, null: false
      add :balance_after, :integer, null: false

      # Related entities
      add :from_user_id, :string # User who sent (for gifts/transfers)
      add :to_user_id, :string   # User who received (for gifts/transfers)
      add :related_id, :string   # ID of related entity (post, video, gift, etc.)
      add :related_type, :string # Type of related entity

      # Metadata
      add :description, :text
      add :metadata, :map # JSON metadata for additional info

      # Status
      add :status, :string, default: "completed", null: false
      # Status: "pending", "completed", "failed", "refunded"

      timestamps(type: :utc_datetime)
    end

    # Indexes for transactions
    create index(:transactions, [:wallet_id, :inserted_at])
    create index(:transactions, [:transaction_type])
    create index(:transactions, [:from_user_id])
    create index(:transactions, [:to_user_id])
    create index(:transactions, [:status])
    create index(:transactions, [:related_id, :related_type])

    # Check constraint - amount must be positive
    create constraint(:transactions, :amount_positive,
             check: "amount > 0"
           )
  end
end
