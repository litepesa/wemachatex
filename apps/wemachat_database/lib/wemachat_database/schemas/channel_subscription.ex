defmodule WemachatDatabase.Schemas.ChannelSubscription do
  @moduledoc """
  Schema for channel subscriptions - tracks which users are subscribed to which channels.
  Includes unread post tracking and notification preferences (silent by default).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.Channel

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, except: [:__meta__, :channel]}

  schema "channel_subscriptions" do
    field :user_id, :string
    field :unread_count, :integer, default: 0
    field :last_read_at, :utc_datetime
    field :notifications_enabled, :boolean, default: false

    belongs_to :channel, Channel, foreign_key: :channel_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new subscription.
  """
  def create_changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:channel_id, :user_id, :notifications_enabled])
    |> validate_required([:channel_id, :user_id])
    |> unique_constraint([:channel_id, :user_id],
      name: :channel_subscriptions_channel_id_user_id_index,
      message: "user is already subscribed to this channel"
    )
    |> foreign_key_constraint(:channel_id)
  end

  @doc """
  Changeset for marking posts as read (resets unread_count and updates last_read_at).
  """
  def mark_read_changeset(subscription) do
    subscription
    |> cast(%{unread_count: 0, last_read_at: DateTime.utc_now()}, [
      :unread_count,
      :last_read_at
    ])
  end

  @doc """
  Changeset for incrementing unread count when a new post is published.
  """
  def increment_unread_changeset(subscription) do
    new_count = (subscription.unread_count || 0) + 1

    subscription
    |> cast(%{unread_count: new_count}, [:unread_count])
  end

  @doc """
  Changeset for updating notification preferences.
  """
  def notification_changeset(subscription, enabled) do
    subscription
    |> cast(%{notifications_enabled: enabled}, [:notifications_enabled])
  end
end
