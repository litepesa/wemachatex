defmodule WemachatDatabase.Schemas.Contact do
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :string

  schema "contacts" do
    belongs_to :user, User, type: :string
    belongs_to :contact_user, User, type: :string
    field :display_name, :string
    field :is_favorite, :boolean, default: false
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:user_id, :contact_user_id, :display_name, :is_favorite, :notes])
    |> validate_required([:user_id, :contact_user_id])
    |> validate_not_self()
    |> unique_constraint([:user_id, :contact_user_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:contact_user_id)
  end

  # Prevent users from adding themselves as contacts
  defp validate_not_self(changeset) do
    user_id = get_field(changeset, :user_id)
    contact_user_id = get_field(changeset, :contact_user_id)

    if user_id && contact_user_id && user_id == contact_user_id do
      add_error(changeset, :contact_user_id, "cannot add yourself as a contact")
    else
      changeset
    end
  end
end
