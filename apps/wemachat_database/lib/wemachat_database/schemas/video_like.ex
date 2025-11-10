defmodule WemachatDatabase.Schemas.VideoLike do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, except: [:__meta__, :video]}

  schema "video_likes" do
    field :user_id, :string
    field :video_id, :binary_id

    timestamps(type: :utc_datetime, updated_at: false)

    # Associations
    belongs_to :video, WemachatDatabase.Schemas.Video, define_field: false
  end

  @doc """
  Changeset for creating a like
  """
  def changeset(like \\ %__MODULE__{}, attrs) do
    like
    |> cast(attrs, [:user_id, :video_id])
    |> validate_required([:user_id, :video_id])
    |> unique_constraint([:user_id, :video_id], message: "Already liked this video")
  end
end
