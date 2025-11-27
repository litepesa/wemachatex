defmodule WemachatDatabase.Schemas.Status do
  @moduledoc """
  Schema for user statuses (WhatsApp-like 24-hour stories).
  Supports text, image, and video with privacy controls and expiration.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.{StatusView, StatusLike}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           except: [:__meta__, :views, :likes]}

  schema "statuses" do
    field :user_id, :string
    field :content, :string
    field :media_url, :string
    field :media_type, :string, default: "text"
    field :thumbnail_url, :string
    field :text_background, :string
    field :visibility, :string, default: "all"
    field :visible_to, {:array, :string}, default: []
    field :hidden_from, {:array, :string}, default: []
    field :duration_seconds, :integer
    field :views_count, :integer, default: 0
    field :likes_count, :integer, default: 0
    field :gifts_count, :integer, default: 0
    field :is_deleted, :boolean, default: false
    field :expires_at, :utc_datetime_usec

    has_many :views, StatusView, foreign_key: :status_id
    has_many :likes, StatusLike, foreign_key: :status_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a status.
  Automatically sets expiration to 24 hours from now.
  """
  def create_changeset(status, attrs) do
    status
    |> cast(attrs, [
      :user_id,
      :content,
      :media_url,
      :media_type,
      :thumbnail_url,
      :text_background,
      :visibility,
      :visible_to,
      :hidden_from,
      :duration_seconds
    ])
    |> validate_required([:user_id, :media_type])
    |> validate_inclusion(:media_type, ["text", "image", "video"])
    |> validate_inclusion(:visibility, ["all", "close_friends", "custom", "only_me"])
    |> validate_content_requirements()
    |> put_expiration()
  end

  @doc """
  Changeset for updating status metadata (views_count, likes_count, gifts_count).
  This is typically called by trigger functions, not manually.
  """
  def metadata_changeset(status, attrs) do
    status
    |> cast(attrs, [:views_count, :likes_count, :gifts_count])
    |> validate_number(:views_count, greater_than_or_equal_to: 0)
    |> validate_number(:likes_count, greater_than_or_equal_to: 0)
    |> validate_number(:gifts_count, greater_than_or_equal_to: 0)
  end

  @doc """
  Changeset for soft-deleting a status.
  """
  def delete_changeset(status, _attrs \\ %{}) do
    change(status, is_deleted: true)
  end

  @doc """
  Checks if a status is visible to a specific user based on privacy settings.
  """
  def visible_to_user?(%__MODULE__{} = status, user_id) do
    cond do
      # Owner can always see their own status
      status.user_id == user_id ->
        true

      # Only me - nobody else can see
      status.visibility == "only_me" ->
        false

      # All - everyone can see except those in hidden_from list
      status.visibility == "all" ->
        user_id not in status.hidden_from

      # Custom - only users in visible_to list can see
      status.visibility == "custom" ->
        user_id in status.visible_to

      # Close friends - return true (actual close friends check should be done at application level)
      status.visibility == "close_friends" ->
        true

      # Default: not visible
      true ->
        false
    end
  end

  # Private helpers

  defp validate_content_requirements(changeset) do
    media_type = get_field(changeset, :media_type)

    case media_type do
      "text" ->
        validate_required(changeset, [:content])
        |> validate_length(:content, min: 1, max: 1000)

      "image" ->
        validate_required(changeset, [:media_url])

      "video" ->
        changeset
        |> validate_required([:media_url])
        |> maybe_validate_duration()

      _ ->
        changeset
    end
  end

  defp put_expiration(changeset) do
    if get_field(changeset, :expires_at) do
      changeset
    else
      expires_at = DateTime.utc_now() |> DateTime.add(24 * 60 * 60, :second)
      put_change(changeset, :expires_at, expires_at)
    end
  end

  defp maybe_validate_duration(changeset) do
    case get_field(changeset, :duration_seconds) do
      nil -> changeset
      _ -> validate_number(changeset, :duration_seconds, greater_than: 0, less_than_or_equal_to: 60)
    end
  end
end
