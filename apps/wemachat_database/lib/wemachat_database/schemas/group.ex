defmodule WemachatDatabase.Schemas.Group do
  @moduledoc """
  Schema for group chat conversations.
  Supports up to 512 members with admin roles and rich features.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.{GroupMember, GroupMessage}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           except: [:__meta__, :members, :messages]}

  schema "groups" do
    field :name, :string
    field :description, :string
    field :group_image_url, :string
    field :creator_id, :string
    field :group_type, :string, default: "private"
    field :member_count, :integer, default: 1
    field :admin_count, :integer, default: 0
    field :subscriber_count, :integer, default: 0
    field :max_members, :integer, default: 512
    field :last_message_text, :string
    field :last_message_at, :utc_datetime_usec
    field :is_active, :boolean, default: true

    has_many :members, GroupMember, foreign_key: :group_id
    has_many :messages, GroupMessage, foreign_key: :group_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a group.
  """
  def create_changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :description, :group_image_url, :creator_id, :group_type, :max_members])
    |> validate_required([:name, :creator_id, :group_type])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 500)
    |> validate_inclusion(:group_type, ["private", "public"])
    |> validate_number(:max_members, greater_than: 0, less_than_or_equal_to: 512)
  end

  @doc """
  Changeset for updating group details.
  """
  def update_changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :description, :group_image_url, :is_active])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 500)
  end

  @doc """
  Changeset for updating group metadata (last message, member count, admin count, subscriber count).
  This is typically called by trigger functions, not manually.
  """
  def metadata_changeset(group, attrs) do
    group
    |> cast(attrs, [:last_message_text, :last_message_at, :member_count, :admin_count, :subscriber_count])
    |> validate_number(:member_count, greater_than_or_equal_to: 0)
    |> validate_number(:admin_count, greater_than_or_equal_to: 0, less_than_or_equal_to: 16)
    |> validate_number(:subscriber_count, greater_than_or_equal_to: 0)
  end
end
