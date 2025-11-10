defmodule WemachatDatabase.Schemas.VideoComment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, except: [:__meta__, :video]}

  schema "video_comments" do
    field :video_id, :binary_id
    field :user_id, :string
    field :comment_text, :string
    field :image_url, :string

    timestamps(type: :utc_datetime)

    # Associations
    belongs_to :video, WemachatDatabase.Schemas.Video, define_field: false
  end

  @doc """
  Changeset for creating a comment
  """
  def create_changeset(comment \\ %__MODULE__{}, attrs) do
    comment
    |> cast(attrs, [:video_id, :user_id, :comment_text, :image_url])
    |> validate_required([:video_id, :user_id, :comment_text])
    |> validate_length(:comment_text, min: 1, max: 500)
  end

  @doc """
  Changeset for updating a comment
  """
  def update_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:comment_text, :image_url])
    |> validate_length(:comment_text, min: 1, max: 500)
  end
end
