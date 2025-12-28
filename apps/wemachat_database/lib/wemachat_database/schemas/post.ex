defmodule WemachatDatabase.Schemas.Post do
  @moduledoc """
  Schema for Moments posts (user status updates).
  Similar to Facebook posts or WeChat Moments.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.{PostLike, PostComment}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           except: [:__meta__, :likes, :comments]}

  @visibility_options ["public", "friends", "private"]
  @media_types ["text", "images", "video", "mixed"]

  schema "posts" do
    # User reference
    field :user_id, :string
    field :user_name, :string
    field :user_image, :string

    # Content
    field :content_text, :string
    field :media_urls, {:array, :string}, default: []
    field :media_type, :string

    # Privacy
    field :visibility, :string, default: "public"
    field :visible_to, {:array, :string}, default: []  # Custom whitelist (WeChat-style) - Firebase UIDs
    field :hidden_from, {:array, :string}, default: [] # Custom blacklist (WeChat-style) - Firebase UIDs
    field :location, :string                           # Location tag

    # Engagement Metrics
    field :likes_count, :integer, default: 0
    field :comments_count, :integer, default: 0
    field :shares_count, :integer, default: 0

    # Status
    field :is_active, :boolean, default: true

    has_many :likes, PostLike, foreign_key: :post_id
    has_many :comments, PostComment, foreign_key: :post_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a post.
  """
  def create_changeset(post, attrs) do
    post
    |> cast(attrs, [:user_id, :user_name, :user_image, :content_text, :media_urls, :media_type, :visibility, :visible_to, :hidden_from, :location])
    |> validate_required([:user_id, :user_name])
    |> validate_post_content()
    |> validate_visibility()
    |> validate_media_type()
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for updating a post.
  """
  def update_changeset(post, attrs) do
    post
    |> cast(attrs, [:content_text, :media_urls, :media_type, :visibility, :visible_to, :hidden_from, :location, :is_active])
    |> validate_post_content()
    |> validate_visibility()
    |> validate_media_type()
  end

  ## Private Functions

  defp validate_post_content(changeset) do
    content_text = get_field(changeset, :content_text)
    media_urls = get_field(changeset, :media_urls) || []

    if is_nil(content_text) and Enum.empty?(media_urls) do
      add_error(changeset, :content_text, "post must have text or media")
    else
      changeset
    end
  end

  defp validate_visibility(changeset) do
    validate_inclusion(changeset, :visibility, @visibility_options)
  end

  defp validate_media_type(changeset) do
    media_type = get_field(changeset, :media_type)

    if media_type && media_type not in @media_types do
      add_error(changeset, :media_type, "must be one of: #{Enum.join(@media_types, ", ")}")
    else
      changeset
    end
  end
end
