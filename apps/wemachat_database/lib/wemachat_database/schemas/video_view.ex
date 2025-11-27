defmodule WemachatDatabase.Schemas.VideoView do
  @moduledoc """
  Tracks which videos users have watched.
  Used by recommendation system to prevent showing the same video twice.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type :string
  @derive {Jason.Encoder, except: [:__meta__, :user, :video]}

  schema "video_views" do
    field :user_id, :string
    field :video_id, :binary_id
    field :watched_at, :utc_datetime_usec
    field :watch_duration_seconds, :integer, default: 0
    field :completed, :boolean, default: false
    field :view_count, :integer, default: 1

    timestamps(type: :utc_datetime_usec)

    # Associations
    belongs_to :user, WemachatDatabase.Schemas.User, type: :string, define_field: false
    belongs_to :video, WemachatDatabase.Schemas.Video, type: :binary_id, define_field: false
  end

  @doc """
  Changeset for creating a video view record.
  """
  def create_changeset(video_view \\ %__MODULE__{}, attrs) do
    video_view
    |> cast(attrs, [:user_id, :video_id, :watch_duration_seconds, :completed])
    |> validate_required([:user_id, :video_id])
    |> put_change(:watched_at, DateTime.utc_now())
    |> unique_constraint([:user_id, :video_id], name: :video_views_user_id_video_id_index)
  end

  @doc """
  Changeset for updating watch duration and view count (for featured video re-shows).
  """
  def update_changeset(video_view, attrs) do
    video_view
    |> cast(attrs, [:watch_duration_seconds, :completed, :view_count, :watched_at])
    |> validate_number(:watch_duration_seconds, greater_than_or_equal_to: 0)
    |> validate_number(:view_count, greater_than_or_equal_to: 1, less_than_or_equal_to: 4)
  end
end
