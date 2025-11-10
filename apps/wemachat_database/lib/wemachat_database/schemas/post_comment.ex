defmodule WemachatDatabase.Schemas.PostComment do
  @moduledoc """
  Schema for comments on Moments posts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.Post

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           except: [:__meta__, :post]}

  schema "post_comments" do
    field :user_id, :string
    field :comment_text, :string
    field :media_url, :string
    field :is_deleted, :boolean, default: false

    belongs_to :post, Post, foreign_key: :post_id, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a comment.
  """
  def create_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:post_id, :user_id, :comment_text, :media_url])
    |> validate_required([:post_id, :user_id, :comment_text])
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for updating a comment.
  """
  def update_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:comment_text, :media_url])
    |> validate_required([:comment_text])
  end

  @doc """
  Changeset for soft-deleting a comment.
  """
  def delete_changeset(comment) do
    comment
    |> change(is_deleted: true)
  end
end
