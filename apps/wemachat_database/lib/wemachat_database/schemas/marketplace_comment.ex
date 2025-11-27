defmodule WemachatDatabase.Schemas.MarketplaceComment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, except: [:__meta__, :item, :user]}

  schema "marketplace_comments" do
    field :item_id, :binary_id
    field :user_id, :string
    field :user_name, :string
    field :user_image, :string

    field :comment_text, :string
    field :media_url, :string  # Optional image attachment

    timestamps(type: :utc_datetime_usec)

    # Associations
    belongs_to :item, WemachatDatabase.Schemas.MarketplaceItem, define_field: false
    belongs_to :user, WemachatDatabase.Schemas.User, type: :string, define_field: false
  end

  @doc """
  Changeset for creating a comment
  """
  def changeset(comment \\ %__MODULE__{}, attrs) do
    comment
    |> cast(attrs, [:item_id, :user_id, :user_name, :user_image, :comment_text, :media_url])
    |> validate_required([:item_id, :user_id, :user_name, :comment_text])
    |> validate_length(:comment_text, min: 1, max: 500)
  end
end
