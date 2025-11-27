defmodule WemachatDatabase.Schemas.MarketplaceLike do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, except: [:__meta__, :item, :user]}

  schema "marketplace_likes" do
    field :item_id, :binary_id
    field :user_id, :string

    timestamps(type: :utc_datetime_usec)

    # Associations
    belongs_to :item, WemachatDatabase.Schemas.MarketplaceItem, define_field: false
    belongs_to :user, WemachatDatabase.Schemas.User, type: :string, define_field: false
  end

  @doc """
  Changeset for creating a like
  """
  def changeset(like \\ %__MODULE__{}, attrs) do
    like
    |> cast(attrs, [:item_id, :user_id])
    |> validate_required([:item_id, :user_id])
    |> unique_constraint([:item_id, :user_id], name: :marketplace_likes_item_id_user_id_index)
  end
end
