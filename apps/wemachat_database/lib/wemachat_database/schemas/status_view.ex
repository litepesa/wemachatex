defmodule WemachatDatabase.Schemas.StatusView do
  @moduledoc """
  Schema for tracking who viewed which status.
  Unique constraint ensures each user can only view a status once.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.Status

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           except: [:__meta__, :status]}

  schema "status_views" do
    field :user_id, :string
    field :viewed_at, :utc_datetime_usec

    belongs_to :status, Status, foreign_key: :status_id, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a status view record.
  Automatically sets viewed_at to current time.
  """
  def create_changeset(status_view, attrs) do
    status_view
    |> cast(attrs, [:status_id, :user_id])
    |> validate_required([:status_id, :user_id])
    |> put_viewed_at()
    |> unique_constraint([:status_id, :user_id], name: :status_views_status_id_user_id_index)
  end

  defp put_viewed_at(changeset) do
    if get_field(changeset, :viewed_at) do
      changeset
    else
      put_change(changeset, :viewed_at, DateTime.utc_now())
    end
  end
end
