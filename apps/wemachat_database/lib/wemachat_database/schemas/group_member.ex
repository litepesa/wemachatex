defmodule WemachatDatabase.Schemas.GroupMember do
  @moduledoc """
  Schema for group membership.
  Tracks users who are part of a group with their roles (admin/member).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.Group

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           except: [:__meta__, :group]}

  @valid_roles ["admin", "member"]

  schema "group_members" do
    field :group_id, :binary_id
    field :user_id, :string
    field :role, :string, default: "member"
    field :joined_at, :utc_datetime_usec
    field :is_active, :boolean, default: true

    belongs_to :group, Group, define_field: false, references: :id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for adding a member to a group.
  """
  def create_changeset(group_member, attrs) do
    group_member
    |> cast(attrs, [:group_id, :user_id, :role])
    |> validate_required([:group_id, :user_id])
    |> validate_inclusion(:role, @valid_roles)
    |> put_change(:joined_at, DateTime.utc_now())
    |> unique_constraint([:group_id, :user_id],
      name: :group_members_group_user_unique,
      message: "User is already a member of this group"
    )
  end

  @doc """
  Changeset for updating member role or status.
  """
  def update_changeset(group_member, attrs) do
    group_member
    |> cast(attrs, [:role, :is_active])
    |> validate_inclusion(:role, @valid_roles)
  end

  @doc """
  Check if member is an admin.
  """
  def admin?(%__MODULE__{role: role}), do: role == "admin"

  @doc """
  Get list of valid roles.
  """
  def valid_roles, do: @valid_roles
end
