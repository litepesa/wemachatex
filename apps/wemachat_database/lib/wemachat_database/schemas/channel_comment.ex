defmodule WemachatDatabase.Schemas.ChannelComment do
  @moduledoc """
  Schema for channel post comments with multi-threaded unlimited nesting.
  Supports Twitter/Reddit-style threaded conversations with media attachments.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.{ChannelPost, ChannelComment}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, except: [:__meta__, :post, :parent, :replies]}

  @media_type_values ~w(image video)a

  schema "channel_comments" do
    field :author_id, :string
    field :text, :string
    field :media_url, :string
    field :media_type, Ecto.Enum, values: @media_type_values
    field :path, {:array, :binary_id}
    field :depth, :integer, default: 0
    field :likes, :integer, default: 0
    field :replies_count, :integer, default: 0
    field :is_pinned, :boolean, default: false

    belongs_to :post, ChannelPost, foreign_key: :post_id
    belongs_to :parent, ChannelComment, foreign_key: :parent_id
    has_many :replies, ChannelComment, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new comment.
  """
  def create_changeset(comment, attrs) do
    comment
    |> cast(attrs, [
      :post_id,
      :author_id,
      :parent_id,
      :text,
      :media_url,
      :media_type
    ])
    |> validate_required([:post_id, :author_id, :text])
    |> validate_length(:text, min: 1, max: 2_000)
    |> validate_inclusion(:media_type, @media_type_values)
    |> validate_media_requirement()
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:parent_id)
    |> build_path()
  end

  @doc """
  Changeset for updating comment text.
  """
  def update_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:text])
    |> validate_required([:text])
    |> validate_length(:text, min: 1, max: 2_000)
  end

  @doc """
  Changeset for updating comment stats (likes, replies_count).
  """
  def stats_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:likes, :replies_count])
    |> validate_number(:likes, greater_than_or_equal_to: 0)
    |> validate_number(:replies_count, greater_than_or_equal_to: 0)
  end

  @doc """
  Changeset for pinning/unpinning a comment.
  """
  def pin_changeset(comment, is_pinned) do
    comment
    |> cast(%{is_pinned: is_pinned}, [:is_pinned])
  end

  # Private functions

  defp validate_media_requirement(changeset) do
    media_url = get_field(changeset, :media_url)
    media_type = get_field(changeset, :media_type)

    cond do
      not is_nil(media_url) and is_nil(media_type) ->
        add_error(changeset, :media_type, "is required when media_url is provided")

      not is_nil(media_type) and is_nil(media_url) ->
        add_error(changeset, :media_url, "is required when media_type is provided")

      true ->
        changeset
    end
  end

  defp build_path(changeset) do
    parent_id = get_field(changeset, :parent_id)

    if is_nil(parent_id) do
      # Top-level comment (no parent)
      changeset
      |> put_change(:path, [])
      |> put_change(:depth, 0)
    else
      # This will be calculated after insert when we have the comment ID
      # The context layer will handle updating the path
      changeset
    end
  end

  @doc """
  Builds the full path for a comment based on its parent.
  Should be called after insert when we have both parent and new comment IDs.
  """
  def update_path_changeset(comment, parent_path, parent_id) do
    new_path = parent_path ++ [parent_id]
    depth = length(new_path)

    comment
    |> cast(%{path: new_path, depth: depth}, [:path, :depth])
  end
end
