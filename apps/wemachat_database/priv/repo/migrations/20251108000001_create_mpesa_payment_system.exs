defmodule WemachatDatabase.Repo.Migrations.CreateMpesaPaymentSystem do
  use Ecto.Migration

  def up do
    # Add payment fields to users table
    alter table(:users) do
      add :has_paid, :boolean, default: false, null: false
      add :payment_date, :utc_datetime_usec
      add :mpesa_transaction_id, :string
      add :payment_amount, :decimal, precision: 10, scale: 2
      add :payment_phone_number, :string
    end

    # Grandfather existing users (mark as paid with amount 0)
    execute """
    UPDATE users
    SET has_paid = true,
        payment_date = inserted_at,
        payment_amount = 0.00
    WHERE inserted_at < NOW()
    """

    # Create M-Pesa payment transactions table
    create table(:mpesa_payment_transactions, primary_key: false) do
      add :id, :string, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :string), null: false
      add :phone_number, :string, null: false
      add :amount, :decimal, precision: 10, scale: 2, null: false, default: 99.00

      # M-Pesa STK Push request data
      add :merchant_request_id, :string
      add :checkout_request_id, :string

      # M-Pesa response data
      add :mpesa_receipt_number, :string
      add :transaction_date, :utc_datetime_usec
      add :result_code, :integer
      add :result_desc, :text

      # Status tracking
      add :status, :string, null: false, default: "pending"

      # Timestamps
      add :initiated_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec

      # Metadata (JSON field)
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for performance
    create index(:users, [:has_paid], where: "has_paid = false")
    create index(:users, [:payment_date])
    create index(:users, [:mpesa_transaction_id])

    create index(:mpesa_payment_transactions, [:user_id])
    create unique_index(:mpesa_payment_transactions, [:checkout_request_id])
    create index(:mpesa_payment_transactions, [:status])
    create index(:mpesa_payment_transactions, [:initiated_at])
    create index(:mpesa_payment_transactions, [:phone_number])

    # Check constraints
    create constraint(:mpesa_payment_transactions, :valid_status,
             check: "status IN ('pending', 'completed', 'failed', 'cancelled', 'timeout')"
           )

    create constraint(:mpesa_payment_transactions, :valid_amount, check: "amount > 0")
  end

  def down do
    drop table(:mpesa_payment_transactions)

    alter table(:users) do
      remove :has_paid
      remove :payment_date
      remove :mpesa_transaction_id
      remove :payment_amount
      remove :payment_phone_number
    end
  end
end
