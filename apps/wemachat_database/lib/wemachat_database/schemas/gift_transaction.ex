defmodule WemachatDatabase.Schemas.GiftTransaction do
  @moduledoc """
  Schema for gift transactions between users.
  Tracks virtual gifts sent in the app with wallet integration.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :string

  schema "gift_transactions" do
    field :gift_id, :string
    field :gift_name, :string
    field :gift_emoji, :string
    field :gift_rarity, :string
    field :price, :integer
    field :recipient_amount, :integer
    field :platform_commission, :integer
    field :context, :string # "profile", "video", "live_stream", "chat"
    field :context_id, :string # ID of video, live stream, chat, etc.
    field :message, :string

    # Foreign keys
    field :sender_id, :string
    field :recipient_id, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(gift_transaction, attrs) do
    gift_transaction
    |> cast(attrs, [
      :gift_id,
      :gift_name,
      :gift_emoji,
      :gift_rarity,
      :price,
      :recipient_amount,
      :platform_commission,
      :context,
      :context_id,
      :message,
      :sender_id,
      :recipient_id
    ])
    |> validate_required([
      :gift_id,
      :gift_name,
      :price,
      :sender_id,
      :recipient_id
    ])
    |> validate_number(:price, greater_than: 0)
    |> validate_number(:recipient_amount, greater_than_or_equal_to: 0)
    |> validate_number(:platform_commission, greater_than_or_equal_to: 0)
    |> validate_inclusion(:context, ["profile", "video", "live_stream", "chat"])
  end
end
