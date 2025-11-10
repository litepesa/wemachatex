defmodule WemachatDatabase.Schemas.MpesaPaymentTransaction do
  @moduledoc """
  Schema for M-Pesa payment transactions.
  Handles both:
  1. One-time KES 99 activation payment
  2. Wallet top-up transactions (adds coins to user balance)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.User

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  @derive {Jason.Encoder, except: [:__meta__, :user]}

  schema "mpesa_payment_transactions" do
    field :phone_number, :string
    field :amount, :decimal
    field :merchant_request_id, :string
    field :checkout_request_id, :string
    field :mpesa_receipt_number, :string
    field :transaction_date, :utc_datetime_usec
    field :result_code, :integer
    field :result_desc, :string
    field :status, :string, default: "pending"
    field :initiated_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :user, User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new payment transaction (STK Push initiation).
  """
  def create_changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :user_id,
      :phone_number,
      :amount,
      :merchant_request_id,
      :checkout_request_id,
      :status,
      :initiated_at,
      :metadata
    ])
    |> validate_required([:user_id, :phone_number, :amount, :initiated_at])
    |> validate_number(:amount, greater_than: 0)
    |> validate_inclusion(:status, ["pending", "completed", "failed", "cancelled", "timeout"])
    |> unique_constraint(:checkout_request_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for updating transaction after M-Pesa callback.
  """
  def callback_changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :mpesa_receipt_number,
      :transaction_date,
      :result_code,
      :result_desc,
      :status,
      :completed_at
    ])
    |> validate_required([:result_code, :result_desc, :status])
    |> validate_inclusion(:status, ["completed", "failed", "cancelled", "timeout"])
  end

  @doc """
  Changeset for updating only the status (e.g., from query).
  """
  def status_changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [:status, :completed_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, ["pending", "completed", "failed", "cancelled", "timeout"])
  end
end
