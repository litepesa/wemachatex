defmodule WemachatDatabase.Schemas.StatusLike do
  @moduledoc """
  Schema for tracking who liked which status.
  Unique constraint ensures each user can only like a status once.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.Status

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           except: [:__meta__, :status]}

  schema "status_likes" do
    field :user_id, :string

    belongs_to :status, Status, foreign_key: :status_id, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a status like record.
  """
  def create_changeset(status_like, attrs) do
    status_like
    |> cast(attrs, [:status_id, :user_id])
    |> validate_required([:status_id, :user_id])
    |> unique_constraint([:status_id, :user_id], name: :status_likes_status_id_user_id_index)
  end
end
