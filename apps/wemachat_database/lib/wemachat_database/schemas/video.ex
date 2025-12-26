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

    # Recommendation & Admin Control Fields
    field :admin_boost_score, :integer, default: 0
    field :target_counties, {:array, :string}
    field :target_constituencies, {:array, :string}
    field :target_wards, {:array, :string}
    field :is_pinned, :boolean, default: false
    field :visibility_level, :string, default: "public"
    field :recommendation_score, :decimal, default: Decimal.new("0.0")

    # Silent Push System (no notifications, just feed influence)
    field :push_to_all, :boolean, default: false
    field :push_to_counties, {:array, :string}
    field :push_to_constituencies, {:array, :string}
    field :push_to_wards, {:array, :string}
    field :pushed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)

    # Associations
    belongs_to :user, WemachatDatabase.Schemas.User, type: :string, define_field: false
    has_many :video_likes, WemachatDatabase.Schemas.VideoLike
    has_many :video_comments, WemachatDatabase.Schemas.VideoComment
  end

  @doc """
  Changeset for creating a video.
  Videos no longer expire and stay on the platform permanently.
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

  @doc """
  Changeset for admin moderation operations (recommendation system)
  """
  def admin_changeset(video, attrs) do
    video
    |> cast(attrs, [
      :admin_boost_score,
      :target_counties,
      :target_constituencies,
      :target_wards,
      :is_pinned,
      :visibility_level,
      :recommendation_score,
      :push_to_all,
      :push_to_counties,
      :push_to_constituencies,
      :push_to_wards,
      :pushed_at
    ])
    |> validate_number(:admin_boost_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_inclusion(:visibility_level, ["public", "limited", "hidden"])
  end

  @doc """
  Check if video is active (is_active = true).
  """
  def active?(%__MODULE__{} = video) do
    video.is_active
  end

  # Recommendation System Pattern Matching

  @doc """
  Check if video is pinned (always shown first)
  """
  def pinned?(%__MODULE__{is_pinned: true}), do: true
  def pinned?(_), do: false

  @doc """
  Check if video is publicly visible
  """
  def public?(%__MODULE__{visibility_level: "public"}), do: true
  def public?(_), do: false

  @doc """
  Check if video is hidden from recommendations
  """
  def hidden?(%__MODULE__{visibility_level: "hidden"}), do: true
  def hidden?(_), do: false

  @doc """
  Check if video has admin boost
  """
  def boosted?(%__MODULE__{admin_boost_score: score}) when score > 0, do: true
  def boosted?(_), do: false

  @doc """
  Check if video is geo-targeted
  """
  def geo_targeted?(%__MODULE__{target_counties: counties}) when is_list(counties) and length(counties) > 0, do: true
  def geo_targeted?(%__MODULE__{target_constituencies: constituencies}) when is_list(constituencies) and length(constituencies) > 0, do: true
  def geo_targeted?(%__MODULE__{target_wards: wards}) when is_list(wards) and length(wards) > 0, do: true
  def geo_targeted?(_), do: false

  @doc """
  Check if video should be visible in recommendations
  """
  def visible_in_recommendations?(%__MODULE__{visibility_level: "hidden"}), do: false
  def visible_in_recommendations?(%__MODULE__{is_active: false}), do: false
  def visible_in_recommendations?(_), do: true

  @doc """
  Get recency tier based on video age
  Returns :fresh (0-24h), :recent (24-48h), :moderate (48-72h), or :old (72h+)
  """
  def recency_tier(%__MODULE__{inserted_at: inserted_at}) do
    now = DateTime.utc_now()
    hours_old = DateTime.diff(now, inserted_at, :hour)

    cond do
      hours_old < 24 -> :fresh
      hours_old < 48 -> :recent
      hours_old < 72 -> :moderate
      true -> :old
    end
  end

  @doc """
  Check if video matches user's location (for geo-targeted content)
  """
  def matches_location?(%__MODULE__{} = video, user_county, user_constituency, user_ward) do
    cond do
      # No targeting = show to everyone
      not geo_targeted?(video) -> true

      # Check ward first (most specific)
      video.target_wards && user_ward in video.target_wards -> true

      # Then constituency
      video.target_constituencies && user_constituency in video.target_constituencies -> true

      # Then county (least specific)
      video.target_counties && user_county in video.target_counties -> true

      # No match
      true -> false
    end
  end

  # Silent Push System Pattern Matching

  @doc """
  Check if video is pushed to all users (highest priority)
  """
  def pushed_to_all?(%__MODULE__{push_to_all: true}), do: true
  def pushed_to_all?(_), do: false

  @doc """
  Check if video has any push settings enabled
  """
  def pushed?(%__MODULE__{push_to_all: true}), do: true
  def pushed?(%__MODULE__{push_to_counties: counties}) when is_list(counties) and length(counties) > 0, do: true
  def pushed?(%__MODULE__{push_to_constituencies: constituencies}) when is_list(constituencies) and length(constituencies) > 0, do: true
  def pushed?(%__MODULE__{push_to_wards: wards}) when is_list(wards) and length(wards) > 0, do: true
  def pushed?(_), do: false

  @doc """
  Check if video is pushed to user's location (silent push, no notification)
  Push precedence: push_to_all > push_to_counties > push_to_constituencies > push_to_wards
  """
  def pushed_to_user?(%__MODULE__{push_to_all: true}, _county, _constituency, _ward), do: true
  def pushed_to_user?(%__MODULE__{push_to_counties: counties}, user_county, _constituency, _ward) when is_list(counties) do
    user_county in counties
  end
  def pushed_to_user?(%__MODULE__{push_to_constituencies: constituencies}, _county, user_constituency, _ward) when is_list(constituencies) do
    user_constituency in constituencies
  end
  def pushed_to_user?(%__MODULE__{push_to_wards: wards}, _county, _constituency, user_ward) when is_list(wards) do
    user_ward in wards
  end
  def pushed_to_user?(_video, _county, _constituency, _ward), do: false
end
