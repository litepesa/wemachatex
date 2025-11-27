defmodule WemachatDatabase.Schemas.Wallet do
  @moduledoc """
  Schema for user wallet (virtual coin balance).
  Each user has one wallet.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.Transaction

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           except: [:__meta__, :transactions]}

  schema "wallets" do
    field :user_id, :string
    field :username, :string
    field :phone_number, :string
    field :mpesa_number, :string
    field :balance, :integer, default: 0
    field :total_earned, :integer, default: 0
    field :total_spent, :integer, default: 0
    field :is_active, :boolean, default: true

    has_many :transactions, Transaction, foreign_key: :wallet_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a wallet.
  """
  def create_changeset(wallet, attrs) do
    wallet
    |> cast(attrs, [:user_id, :username, :phone_number, :mpesa_number, :balance, :total_earned, :total_spent])
    |> validate_required([:user_id])
    |> validate_number(:balance, greater_than_or_equal_to: 0)
    |> validate_number(:total_earned, greater_than_or_equal_to: 0)
    |> validate_number(:total_spent, greater_than_or_equal_to: 0)
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for updating wallet balance.
  """
  def update_changeset(wallet, attrs) do
    wallet
    |> cast(attrs, [:balance, :total_earned, :total_spent, :is_active])
    |> validate_number(:balance, greater_than_or_equal_to: 0)
    |> validate_number(:total_earned, greater_than_or_equal_to: 0)
    |> validate_number(:total_spent, greater_than_or_equal_to: 0)
  end
end
