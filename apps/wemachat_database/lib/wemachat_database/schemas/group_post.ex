defmodule WemachatDatabase.Schemas.GroupPost do
  @moduledoc """
  Schema for posts in public groups (broadcast channels).
  Only owner and admins can create posts. Subscribers can comment.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.{Group, GroupPostComment}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, except: [:__meta__, :group, :comments]}

  @content_type_values ~w(text image video audio document)a

  schema "group_posts" do
    field :author_id, :string
    field :content_type, Ecto.Enum, values: @content_type_values, default: :text
    field :text, :string
    field :media_url, :string
    field :media_urls, {:array, :string}
    field :media_thumbnail_url, :string
    field :media_type, :string
    field :likes, :integer, default: 0
    field :comments_count, :integer, default: 0
    field :views, :integer, default: 0
    field :is_pinned, :boolean, default: false

    belongs_to :group, Group, foreign_key: :group_id
    has_many :comments, GroupPostComment, foreign_key: :post_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new post.
  """
  def create_changeset(post, attrs) do
    post
    |> cast(attrs, [
      :group_id,
      :author_id,
      :content_type,
      :text,
      :media_url,
      :media_urls,
      :media_thumbnail_url,
      :media_type
    ])
    |> validate_required([:group_id, :author_id, :content_type])
    |> validate_inclusion(:content_type, @content_type_values)
    |> validate_content_requirements()
    |> foreign_key_constraint(:group_id)
  end

  @doc """
  Changeset for updating post text.
  """
  def update_changeset(post, attrs) do
    post
    |> cast(attrs, [:text])
    |> validate_length(:text, max: 10_000)
  end

  @doc """
  Changeset for updating post stats (likes, comments_count, views).
  """
  def stats_changeset(post, attrs) do
    post
    |> cast(attrs, [:likes, :comments_count, :views])
    |> validate_number(:likes, greater_than_or_equal_to: 0)
    |> validate_number(:comments_count, greater_than_or_equal_to: 0)
    |> validate_number(:views, greater_than_or_equal_to: 0)
  end

  @doc """
  Changeset for pinning/unpinning a post.
  """
  def pin_changeset(post, is_pinned) do
    post
    |> cast(%{is_pinned: is_pinned}, [:is_pinned])
  end

  # Private functions

  defp validate_content_requirements(changeset) do
    content_type = get_field(changeset, :content_type)
    text = get_field(changeset, :text)
    media_url = get_field(changeset, :media_url)
    media_urls = get_field(changeset, :media_urls)

    case content_type do
      :text ->
        if is_nil(text) or String.trim(text) == "" do
          add_error(changeset, :text, "is required for text posts")
        else
          changeset
          |> validate_length(:text, max: 10_000)
        end

      :image ->
        if is_nil(media_urls) or Enum.empty?(media_urls) do
          add_error(changeset, :media_urls, "is required for image posts")
        else
          changeset
          |> validate_length(:media_urls, max: 10, message: "maximum 10 images allowed")
        end

      type when type in [:video, :audio, :document] ->
        if is_nil(media_url) or String.trim(media_url) == "" do
          add_error(changeset, :media_url, "is required for #{type} posts")
        else
          changeset
        end

      _ ->
        changeset
    end
  end
end
