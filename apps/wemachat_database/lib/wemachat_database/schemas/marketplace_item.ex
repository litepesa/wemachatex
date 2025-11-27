defmodule WemachatDatabase.Schemas.MarketplaceItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, except: [:__meta__, :user]}

  schema "marketplace_items" do
    # User reference (seller)
    field :user_id, :string
    field :user_name, :string
    field :user_image, :string

    # Media URLs (same as videos - can be video OR images)
    field :video_url, :string
    field :thumbnail_url, :string

    # Content
    field :caption, :string
    field :tags, {:array, :string}, default: []

    # Price (main difference from regular videos)
    field :price, :decimal, default: Decimal.new("0.0")

    # Engagement Metrics
    field :views, :integer, default: 0
    field :likes, :integer, default: 0
    field :comments, :integer, default: 0
    field :shares, :integer, default: 0

    # Status Flags
    field :is_active, :boolean, default: true
    field :is_featured, :boolean, default: false
    field :is_verified, :boolean, default: false

    # Boost System (same as videos)
    field :is_boosted, :boolean, default: false
    field :boost_tier, :string, default: "none"
    field :super_boost, :boolean, default: false

    # Multiple Images Support (same as videos)
    field :is_multiple_images, :boolean, default: false
    field :image_urls, {:array, :string}, default: []

    # NO EXPIRY (main difference from videos - marketplace items don't expire)

    # Recommendation & Admin Control Fields (same as videos)
    field :admin_boost_score, :integer, default: 0
    field :target_counties, {:array, :string}
    field :target_constituencies, {:array, :string}
    field :target_wards, {:array, :string}
    field :is_pinned, :boolean, default: false
    field :visibility_level, :string, default: "public"
    field :recommendation_score, :decimal, default: Decimal.new("0.0")

    timestamps(type: :utc_datetime_usec)

    # Associations
    belongs_to :user, WemachatDatabase.Schemas.User, type: :string, define_field: false
    has_many :marketplace_likes, WemachatDatabase.Schemas.MarketplaceLike, foreign_key: :item_id
    has_many :marketplace_comments, WemachatDatabase.Schemas.MarketplaceComment, foreign_key: :item_id
  end

  @doc """
  Changeset for creating a marketplace item.
  No expiry is set (unlike videos).
  """
  def create_changeset(item \\ %__MODULE__{}, attrs) do
    item
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
    |> validate_required([:user_id, :user_name])
    |> validate_video_or_images()
    |> validate_length(:caption, max: 2200)
    |> validate_inclusion(:boost_tier, ["none", "basic", "standard", "advanced"])
    |> validate_number(:price, greater_than_or_equal_to: 0)
  end

  @doc """
  Changeset for updating a marketplace item
  """
  def update_changeset(item, attrs) do
    item
    |> cast(attrs, [
      :caption,
      :tags,
      :price,
      :is_active,
      :is_boosted,
      :boost_tier,
      :super_boost
    ])
    |> validate_length(:caption, max: 2200)
    |> validate_inclusion(:boost_tier, ["none", "basic", "standard", "advanced"])
    |> validate_number(:price, greater_than_or_equal_to: 0)
  end

  @doc """
  Changeset for updating engagement metrics
  """
  def metrics_changeset(item, attrs) do
    item
    |> cast(attrs, [:views, :likes, :comments, :shares])
  end

  @doc """
  Changeset for admin moderation operations (recommendation system)
  """
  def admin_changeset(item, attrs) do
    item
    |> cast(attrs, [
      :admin_boost_score,
      :target_counties,
      :target_constituencies,
      :target_wards,
      :is_pinned,
      :visibility_level,
      :recommendation_score
    ])
    |> validate_number(:admin_boost_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_inclusion(:visibility_level, ["public", "limited", "hidden"])
  end

  # Private Functions

  defp validate_video_or_images(changeset) do
    video_url = get_field(changeset, :video_url)
    is_multiple_images = get_field(changeset, :is_multiple_images)
    image_urls = get_field(changeset, :image_urls)

    cond do
      # If it's a video post, require video_url
      !is_multiple_images && (is_nil(video_url) || video_url == "") ->
        add_error(changeset, :video_url, "is required for video posts")

      # If it's an image post, require at least one image
      is_multiple_images && (is_nil(image_urls) || image_urls == []) ->
        add_error(changeset, :image_urls, "at least one image is required for image posts")

      true ->
        changeset
    end
  end

  # Helper Functions (same as videos)

  @doc """
  Check if item is active
  """
  def active?(%__MODULE__{is_active: is_active}), do: is_active

  @doc """
  Check if item is publicly visible
  """
  def public?(%__MODULE__{visibility_level: "public"}), do: true
  def public?(_), do: false

  @doc """
  Check if item is hidden from recommendations
  """
  def hidden?(%__MODULE__{visibility_level: "hidden"}), do: true
  def hidden?(_), do: false

  @doc """
  Check if item has admin boost
  """
  def boosted?(%__MODULE__{admin_boost_score: score}) when score > 0, do: true
  def boosted?(_), do: false

  @doc """
  Check if item is geo-targeted
  """
  def geo_targeted?(%__MODULE__{target_counties: counties}) when is_list(counties) and length(counties) > 0, do: true
  def geo_targeted?(%__MODULE__{target_constituencies: constituencies}) when is_list(constituencies) and length(constituencies) > 0, do: true
  def geo_targeted?(%__MODULE__{target_wards: wards}) when is_list(wards) and length(wards) > 0, do: true
  def geo_targeted?(_), do: false

  @doc """
  Check if item should be visible in recommendations
  """
  def visible_in_recommendations?(%__MODULE__{visibility_level: "hidden"}), do: false
  def visible_in_recommendations?(%__MODULE__{is_active: false}), do: false
  def visible_in_recommendations?(_), do: true

  @doc """
  Check if item matches user's location (for geo-targeted content)
  """
  def matches_location?(%__MODULE__{} = item, user_county, user_constituency, user_ward) do
    cond do
      # No targeting = show to everyone
      not geo_targeted?(item) -> true

      # Check ward first (most specific)
      item.target_wards && user_ward in item.target_wards -> true

      # Then constituency
      item.target_constituencies && user_constituency in item.target_constituencies -> true

      # Then county (least specific)
      item.target_counties && user_county in item.target_counties -> true

      # No match
      true -> false
    end
  end

  @doc """
  Get recency tier based on item age
  Returns :new (0-7 days), :recent (7-30 days), :old (30+ days)
  """
  def recency_tier(%__MODULE__{inserted_at: inserted_at}) do
    now = DateTime.utc_now()
    days_old = div(DateTime.diff(now, inserted_at, :second), 86400)

    cond do
      days_old < 7 -> :new
      days_old < 30 -> :recent
      true -> :old
    end
  end
end
