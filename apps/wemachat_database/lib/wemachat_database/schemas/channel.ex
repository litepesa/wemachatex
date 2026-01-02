defmodule WemachatDatabase.Schemas.Channel do
  @moduledoc """
  Schema for channels - broadcast content hubs similar to Telegram/WhatsApp channels.
  Supports public, private, and premium channel types with up to 8 admins/moderators.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.{ChannelPost, ChannelMember, ChannelSubscription}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, except: [:__meta__, :posts, :members, :subscriptions]}

  @type_values ~w(public private premium)a

  schema "channels" do
    field :name, :string
    field :description, :string
    field :owner_id, :string
    field :type, Ecto.Enum, values: @type_values, default: :public
    field :subscription_price_coins, :integer
    field :is_verified, :boolean, default: false
    field :subscriber_count, :integer, default: 0
    field :post_count, :integer, default: 0
    field :avatar_url, :string
    field :banner_url, :string

    has_many :posts, ChannelPost, foreign_key: :channel_id
    has_many :members, ChannelMember, foreign_key: :channel_id
    has_many :subscriptions, ChannelSubscription, foreign_key: :channel_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new channel.
  """
  def create_changeset(channel, attrs) do
    channel
    |> cast(attrs, [
      :name,
      :description,
      :owner_id,
      :type,
      :subscription_price_coins,
      :avatar_url,
      :banner_url
    ])
    |> validate_required([:name, :description, :owner_id, :type])
    |> validate_length(:name, min: 3, max: 50)
    |> validate_length(:description, min: 10, max: 500)
    |> validate_inclusion(:type, @type_values)
    |> validate_premium_pricing()
    |> unique_constraint(:name, message: "This channel name is already taken. Please choose a different name.")
  end

  @doc """
  Changeset for updating channel information.
  """
  def update_changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :description, :avatar_url, :banner_url, :is_verified])
    |> validate_length(:name, min: 3, max: 50)
    |> validate_length(:description, min: 10, max: 500)
    |> unique_constraint(:name, message: "This channel name is already taken. Please choose a different name.")
  end

  @doc """
  Changeset for updating channel stats (subscriber_count, post_count).
  """
  def stats_changeset(channel, attrs) do
    channel
    |> cast(attrs, [:subscriber_count, :post_count])
    |> validate_number(:subscriber_count, greater_than_or_equal_to: 0)
    |> validate_number(:post_count, greater_than_or_equal_to: 0)
  end

  # Private functions

  defp validate_premium_pricing(changeset) do
    type = get_field(changeset, :type)
    price = get_field(changeset, :subscription_price_coins)

    case type do
      :premium ->
        changeset
        |> validate_required([:subscription_price_coins])
        |> validate_number(:subscription_price_coins, greater_than: 0)

      _ ->
        changeset
    end
  end
end
