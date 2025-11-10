defmodule WemachatDatabase.Schemas.Transaction do
  @moduledoc """
  Schema for wallet transactions (history of all coin movements).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.Wallet

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           except: [:__meta__, :wallet]}

  @transaction_types [
    "earn",           # Earned coins (daily login, achievements, etc.)
    "spend",          # Spent coins (unlocking content, etc.)
    "gift_sent",      # Sent gift to another user
    "gift_received",  # Received gift from another user
    "purchase",       # Purchased coins (real money)
    "refund",         # Refund of previous transaction
    "admin_credit",   # Admin added coins
    "admin_debit"     # Admin removed coins
  ]

  @status_options ["pending", "completed", "failed", "refunded"]

  schema "transactions" do
    field :transaction_type, :string
    field :amount, :integer
    field :balance_before, :integer
    field :balance_after, :integer
    field :from_user_id, :string
    field :to_user_id, :string
    field :related_id, :string
    field :related_type, :string
    field :description, :string
    field :metadata, :map
    field :status, :string, default: "completed"

    belongs_to :wallet, Wallet, foreign_key: :wallet_id, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a transaction.
  """
  def create_changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :wallet_id,
      :transaction_type,
      :amount,
      :balance_before,
      :balance_after,
      :from_user_id,
      :to_user_id,
      :related_id,
      :related_type,
      :description,
      :metadata,
      :status
    ])
    |> validate_required([:wallet_id, :transaction_type, :amount, :balance_before, :balance_after])
    |> validate_number(:amount, greater_than: 0)
    |> validate_inclusion(:transaction_type, @transaction_types)
    |> validate_inclusion(:status, @status_options)
    |> foreign_key_constraint(:wallet_id)
  end

  @doc """
  Changeset for updating transaction status.
  """
  def update_status_changeset(transaction, status) do
    transaction
    |> cast(%{status: status}, [:status])
    |> validate_inclusion(:status, @status_options)
  end

  @doc """
  Get list of valid transaction types.
  """
  def transaction_types, do: @transaction_types

  @doc """
  Get list of valid status options.
  """
  def status_options, do: @status_options
end
