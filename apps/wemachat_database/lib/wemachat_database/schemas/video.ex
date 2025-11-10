defmodule WemachatDatabase.Schemas.Video do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, except: [:__meta__, :user]}

  schema "videos" do
    # User reference (videos belong to users, not channels)
    field :user_id, :string
    field :user_name, :string
    field :user_image, :string

    # Media URLs
    field :video_url, :string
    field :thumbnail_url, :string

    # Content
    field :caption, :string
    field :tags, {:array, :string}, default: []

    # Engagement Metrics
    field :views, :integer, default: 0
    field :likes, :integer, default: 0
    field :comments, :integer, default: 0
    field :shares, :integer, default: 0

    # Status Flags
    field :is_active, :boolean, default: true
    field :is_featured, :boolean, default: false

    # Boost System
    field :is_boosted, :boolean, default: false
    field :boost_tier, :string, default: "none"
    field :super_boost, :boolean, default: false

    # Premium Content
    field :price, :decimal, default: Decimal.new("0.0")

    # Multiple Images Support
    field :is_multiple_images, :boolean, default: false
    field :image_urls, {:array, :string}, default: []

    # 72-HOUR EXPIRY (RFC 3339 with microseconds)
    field :expires_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)

    # Associations
    belongs_to :user, WemachatDatabase.Schemas.User, type: :string, define_field: false
    has_many :video_likes, WemachatDatabase.Schemas.VideoLike
    has_many :video_comments, WemachatDatabase.Schemas.VideoComment
  end

  @doc """
  Changeset for creating a video.
  Automatically sets expires_at to 72 hours from now.
  """
  def create_changeset(video \\ %__MODULE__{}, attrs) do
    video
    |> cast(attrs, [
      :user_id,
      :user_name,
      :user_image,
      :video_url,
      :thumbnail_url,
      :caption,
      :tags,
      :price,
      :is_multiple_images,
      :image_urls,
      :is_boosted,
      :boost_tier,
      :super_boost
    ])
    |> validate_required([:user_id, :user_name, :video_url])
    |> validate_length(:caption, max: 2200)
    |> validate_inclusion(:boost_tier, ["none", "basic", "standard", "advanced"])
    |> put_expires_at()
  end

  @doc """
  Changeset for updating a video
  """
  def update_changeset(video, attrs) do
    video
    |> cast(attrs, [
      :caption,
      :tags,
      :is_active,
      :is_boosted,
      :boost_tier,
      :super_boost
    ])
    |> validate_length(:caption, max: 2200)
    |> validate_inclusion(:boost_tier, ["none", "basic", "standard", "advanced"])
  end

  @doc """
  Changeset for updating engagement metrics
  """
  def metrics_changeset(video, attrs) do
    video
    |> cast(attrs, [:views, :likes, :comments, :shares])
  end

  # Private Functions

  defp put_expires_at(changeset) do
    # Set expires_at to 72 hours from now (RFC 3339 with microseconds supported)
    expires_at = DateTime.add(DateTime.utc_now(), 72, :hour)
    put_change(changeset, :expires_at, expires_at)
  end

  @doc """
  Check if video is expired
  """
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Check if video is active (not expired and is_active = true)
  """
  def active?(%__MODULE__{} = video) do
    video.is_active and not expired?(video)
  end
end
