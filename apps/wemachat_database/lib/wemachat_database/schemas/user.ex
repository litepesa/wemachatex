defmodule WemachatDatabase.Schemas.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @derive {Jason.Encoder, except: [:__meta__]}

  schema "users" do
    # Core Profile Fields
    field :phone_number, :string
    field :whatsapp_number, :string
    field :name, :string
    field :bio, :string
    field :profile_image, :string
    field :cover_image, :string

    # Engagement Metrics
    field :followers_count, :integer, default: 0
    field :following_count, :integer, default: 0
    field :videos_count, :integer, default: 0
    field :likes_count, :integer, default: 0

    # Status Flags
    field :is_verified, :boolean, default: false
    field :is_active, :boolean, default: true
    field :is_featured, :boolean, default: false
    field :is_live, :boolean, default: false

    # Permission/Role Fields (Staff)
    field :is_admin, :boolean, default: false
    field :is_moderator, :boolean, default: false

    # Restriction Fields (Bans)
    field :can_comment, :boolean, default: true
    field :can_post, :boolean, default: true

    # Privacy Settings
    field :who_can_message, :string, default: "everyone"
    field :who_can_call, :string, default: "everyone"
    field :show_online_status, :boolean, default: true

    # Demographics (Kenya-specific)
    field :gender, :string
    field :location, :string
    field :language, :string

    # Arrays (PostgreSQL arrays)
    field :tags, {:array, :string}, default: []
    field :follower_uids, {:array, :string}, default: []
    field :following_uids, {:array, :string}, default: []
    field :liked_videos, {:array, :string}, default: []

    # Preferences (JSONB)
    field :preferences, :map, default: %{
      "autoPlay" => true,
      "receiveNotifications" => true,
      "darkMode" => false
    }

    # Timestamps (RFC 3339 with microseconds)
    field :last_seen, :utc_datetime_usec
    field :last_post_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new user (from Firebase auth)
  """
  def create_changeset(user \\ %__MODULE__{}, attrs) do
    user
    |> cast(attrs, [
      :id,
      :phone_number,
      :whatsapp_number,
      :name,
      :bio,
      :profile_image,
      :cover_image,
      :gender,
      :location,
      :language,
      :preferences
    ])
    |> validate_required([:id, :phone_number, :name])
    |> validate_length(:name, min: 2, max: 50)
    |> validate_length(:bio, max: 160)
    |> validate_length(:location, max: 255)
    |> validate_length(:language, max: 100)
    |> validate_inclusion(:gender, ["male", "female"], message: "must be 'male' or 'female'")
    |> validate_phone_number(:phone_number)
    |> validate_whatsapp_number(:whatsapp_number)
    |> unique_constraint(:phone_number)
    |> put_default_timestamps()
  end

  @doc """
  Changeset for updating user profile
  """
  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :name,
      :bio,
      :profile_image,
      :cover_image,
      :whatsapp_number,
      :gender,
      :location,
      :language,
      :tags,
      :preferences,
      :who_can_message,
      :who_can_call,
      :show_online_status
    ])
    |> validate_length(:name, min: 2, max: 50)
    |> validate_length(:bio, max: 160)
    |> validate_length(:location, max: 255)
    |> validate_length(:language, max: 100)
    |> validate_inclusion(:gender, ["male", "female"], message: "must be 'male' or 'female'")
    |> validate_inclusion(:who_can_message, ["everyone", "contacts", "nobody"])
    |> validate_inclusion(:who_can_call, ["everyone", "contacts", "nobody"])
    |> validate_whatsapp_number(:whatsapp_number)
  end

  @doc """
  Changeset for updating privacy settings only
  """
  def privacy_changeset(user, attrs) do
    user
    |> cast(attrs, [:who_can_message, :who_can_call, :show_online_status])
    |> validate_inclusion(:who_can_message, ["everyone", "contacts", "nobody"])
    |> validate_inclusion(:who_can_call, ["everyone", "contacts", "nobody"])
  end

  @doc """
  Changeset for admin operations (roles, bans, verification)
  """
  def admin_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :is_verified,
      :is_featured,
      :is_admin,
      :is_moderator,
      :can_comment,
      :can_post,
      :is_active
    ])
    |> validate_required([
      :is_verified,
      :is_featured,
      :is_admin,
      :is_moderator,
      :can_comment,
      :can_post,
      :is_active
    ])
  end

  @doc """
  Changeset for updating engagement metrics
  """
  def metrics_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :followers_count,
      :following_count,
      :videos_count,
      :likes_count
    ])
  end

  @doc """
  Changeset for updating last_seen timestamp
  """
  def last_seen_changeset(user) do
    change(user, last_seen: DateTime.utc_now() |> DateTime.truncate(:microsecond))
  end

  @doc """
  Changeset for updating live streaming status
  """
  def live_status_changeset(user, is_live) do
    change(user, is_live: is_live)
  end

  # Custom Validations

  defp validate_phone_number(changeset, field) do
    validate_change(changeset, field, fn _, phone_number ->
      if String.length(phone_number) >= 10 && String.length(phone_number) <= 15 do
        []
      else
        [{field, "must be between 10 and 15 characters"}]
      end
    end)
  end

  defp validate_whatsapp_number(changeset, field) do
    validate_change(changeset, field, fn _, whatsapp_number ->
      # Kenya format: 254XXXXXXXXX (12 digits)
      if is_nil(whatsapp_number) || whatsapp_number == "" do
        []
      else
        if Regex.match?(~r/^254\d{9}$/, whatsapp_number) do
          []
        else
          [{field, "must be in format 254XXXXXXXXX for Kenyan numbers"}]
        end
      end
    end)
  end

  defp put_default_timestamps(changeset) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    changeset
    |> put_change(:last_seen, now)
  end

  # Helper Functions

  @doc """
  Check if user is staff (admin or moderator)
  """
  def staff?(%__MODULE__{is_admin: true}), do: true
  def staff?(%__MODULE__{is_moderator: true}), do: true
  def staff?(_), do: false

  @doc """
  Check if user can moderate content
  """
  def can_moderate?(%__MODULE__{is_admin: true}), do: true
  def can_moderate?(%__MODULE__{is_moderator: true}), do: true
  def can_moderate?(_), do: false

  @doc """
  Check if user has any restrictions
  """
  def has_restrictions?(%__MODULE__{can_comment: false}), do: true
  def has_restrictions?(%__MODULE__{can_post: false}), do: true
  def has_restrictions?(_), do: false

  @doc """
  Get user type display string
  """
  def user_type_display(%__MODULE__{is_admin: true, is_moderator: true}), do: "Super Admin"
  def user_type_display(%__MODULE__{is_admin: true}), do: "Administrator"
  def user_type_display(%__MODULE__{is_moderator: true}), do: "Moderator"
  def user_type_display(%__MODULE__{is_verified: true}), do: "Verified User"
  def user_type_display(_), do: "User"
end
