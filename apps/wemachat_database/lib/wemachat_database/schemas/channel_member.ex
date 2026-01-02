defmodule WemachatDatabase.Schemas.ChannelMember do
  @moduledoc """
  Schema for channel team members (admins only).
  Each channel can have up to 8 admins.
  The owner is not counted in this table - owner is tracked in channels.owner_id.
  Regular members/subscribers are tracked in channel_subscriptions table.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.Channel

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, except: [:__meta__, :channel]}

  @role_values ~w(admin)a
  @max_members_per_channel 8

  schema "channel_members" do
    field :user_id, :string
    field :role, Ecto.Enum, values: @role_values
    field :added_by, :string

    belongs_to :channel, Channel, foreign_key: :channel_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for adding a new channel member.
  """
  def create_changeset(member, attrs) do
    member
    |> cast(attrs, [:channel_id, :user_id, :role, :added_by])
    |> validate_required([:channel_id, :user_id, :role, :added_by])
    |> validate_inclusion(:role, @role_values)
    |> unique_constraint([:channel_id, :user_id],
      name: :channel_members_channel_id_user_id_index,
      message: "user is already a member of this channel"
    )
    |> foreign_key_constraint(:channel_id)
  end

  @doc """
  Changeset for updating a member's role.
  """
  def role_changeset(member, new_role) do
    member
    |> cast(%{role: new_role}, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, @role_values)
  end

  @doc """
  Returns the maximum number of members allowed per channel.
  """
  def max_members_per_channel, do: @max_members_per_channel
end
