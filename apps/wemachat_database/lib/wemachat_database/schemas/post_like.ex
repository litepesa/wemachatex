defmodule WemachatDatabase.Schemas.PostLike do
  @moduledoc """
  Schema for post likes in Moments.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.Post

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           except: [:__meta__, :post]}

  schema "post_likes" do
    field :user_id, :string

    belongs_to :post, Post, foreign_key: :post_id, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a post like.
  """
  def changeset(post_like, attrs) do
    post_like
    |> cast(attrs, [:post_id, :user_id])
    |> validate_required([:post_id, :user_id])
    |> unique_constraint([:post_id, :user_id],
      name: :post_likes_post_id_user_id_index,
      message: "You have already liked this post"
    )
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:user_id)
  end
end
