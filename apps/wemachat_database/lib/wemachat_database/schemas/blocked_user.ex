defmodule WemachatDatabase.Schemas.BlockedUser do
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :string

  schema "blocked_users" do
    belongs_to :blocker, User, type: :string
    belongs_to :blocked, User, type: :string
    field :reason, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(blocked_user, attrs) do
    blocked_user
    |> cast(attrs, [:blocker_id, :blocked_id, :reason])
    |> validate_required([:blocker_id, :blocked_id])
    |> validate_not_self()
    |> unique_constraint([:blocker_id, :blocked_id])
    |> foreign_key_constraint(:blocker_id)
    |> foreign_key_constraint(:blocked_id)
  end

  # Prevent users from blocking themselves
  defp validate_not_self(changeset) do
    blocker_id = get_field(changeset, :blocker_id)
    blocked_id = get_field(changeset, :blocked_id)

    if blocker_id && blocked_id && blocker_id == blocked_id do
      add_error(changeset, :blocked_id, "cannot block yourself")
    else
      changeset
    end
  end
end
