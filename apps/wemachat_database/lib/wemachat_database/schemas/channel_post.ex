defmodule WemachatDatabase.Schemas.ChannelPost do
  @moduledoc """
  Schema for channel posts - content published in channels.
  Supports 5 content types: text, image, video, audio, document.
  Premium posts require unlocking with coins and support preview duration.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.{Channel, ChannelComment, PostUnlock}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, except: [:__meta__, :channel, :comments, :unlocks]}

  @content_type_values ~w(text image video audio document)a

  schema "channel_posts" do
    field :author_id, :string
    field :content_type, Ecto.Enum, values: @content_type_values, default: :text
    field :text, :string
    field :media_url, :string
    field :media_urls, {:array, :string}
    field :media_thumbnail_url, :string
    field :media_size_bytes, :integer
    field :media_duration_seconds, :integer
    field :is_premium, :boolean, default: false
    field :price_coins, :integer
    field :preview_duration_seconds, :integer
    field :likes, :integer, default: 0
    field :comments_count, :integer, default: 0
    field :views, :integer, default: 0
    field :unlocks, :integer, default: 0

    belongs_to :channel, Channel, foreign_key: :channel_id
    has_many :comments, ChannelComment, foreign_key: :post_id
    has_many :post_unlocks, PostUnlock, foreign_key: :post_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new post.
  """
  def create_changeset(post, attrs) do
    post
    |> cast(attrs, [
      :channel_id,
      :author_id,
      :content_type,
      :text,
      :media_url,
      :media_urls,
      :media_thumbnail_url,
      :media_size_bytes,
      :media_duration_seconds,
      :is_premium,
      :price_coins,
      :preview_duration_seconds
    ])
    |> validate_required([:channel_id, :author_id, :content_type])
    |> validate_inclusion(:content_type, @content_type_values)
    |> validate_content_requirements()
    |> validate_premium_pricing()
    |> validate_media_size()
    |> foreign_key_constraint(:channel_id)
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
  Changeset for updating post stats (likes, comments_count, views, unlocks).
  """
  def stats_changeset(post, attrs) do
    post
    |> cast(attrs, [:likes, :comments_count, :views, :unlocks])
    |> validate_number(:likes, greater_than_or_equal_to: 0)
    |> validate_number(:comments_count, greater_than_or_equal_to: 0)
    |> validate_number(:views, greater_than_or_equal_to: 0)
    |> validate_number(:unlocks, greater_than_or_equal_to: 0)
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

  defp validate_premium_pricing(changeset) do
    is_premium = get_field(changeset, :is_premium)
    price = get_field(changeset, :price_coins)

    case is_premium do
      true ->
        changeset
        |> validate_required([:price_coins])
        |> validate_number(:price_coins, greater_than: 0)
        |> validate_number(:preview_duration_seconds, greater_than_or_equal_to: 0)

      _ ->
        changeset
    end
  end

  defp validate_media_size(changeset) do
    content_type = get_field(changeset, :content_type)
    size_bytes = get_field(changeset, :media_size_bytes)
    is_premium = get_field(changeset, :is_premium)

    cond do
      # Premium posts can be up to 2GB
      is_premium and content_type in [:video, :audio, :document] ->
        changeset
        |> validate_number(:media_size_bytes,
          less_than_or_equal_to: 2_147_483_648,
          message: "premium content cannot exceed 2GB"
        )

      # Regular posts: ≤5 minutes OR ≤100MB
      content_type in [:video, :audio] and not is_nil(size_bytes) ->
        changeset
        |> validate_number(:media_size_bytes,
          less_than_or_equal_to: 104_857_600,
          message: "regular content cannot exceed 100MB"
        )

      true ->
        changeset
    end
  end
end
