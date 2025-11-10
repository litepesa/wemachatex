defmodule WemachatDatabase.Schemas.Call do
  @moduledoc """
  Schema for voice/video calls between users.
  Tracks call history and status.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, except: [:__meta__]}

  @call_types ["audio", "video"]
  @status_options ["pending", "ringing", "active", "ended", "missed", "rejected", "cancelled"]

  schema "calls" do
    field :caller_id, :string
    field :callee_id, :string
    field :call_type, :string
    field :status, :string, default: "pending"
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :duration_seconds, :integer, default: 0
    field :is_deleted, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a call.
  """
  def create_changeset(call, attrs) do
    call
    |> cast(attrs, [:caller_id, :callee_id, :call_type, :status])
    |> validate_required([:caller_id, :callee_id, :call_type])
    |> validate_inclusion(:call_type, @call_types)
    |> validate_inclusion(:status, @status_options)
    |> validate_different_users()
  end

  @doc """
  Changeset for updating call status and timing.
  """
  def update_changeset(call, attrs) do
    call
    |> cast(attrs, [:status, :started_at, :ended_at, :duration_seconds])
    |> validate_inclusion(:status, @status_options)
    |> validate_number(:duration_seconds, greater_than_or_equal_to: 0)
    |> calculate_duration_if_ended()
  end

  @doc """
  Changeset for soft delete.
  """
  def delete_changeset(call) do
    call
    |> cast(%{is_deleted: true}, [:is_deleted])
  end

  @doc """
  Get list of valid call types.
  """
  def call_types, do: @call_types

  @doc """
  Get list of valid status options.
  """
  def status_options, do: @status_options

  ## Helper Functions

  @doc """
  Check if a user is a participant in this call (caller or callee).
  """
  def participant?(call, user_id) do
    call.caller_id == user_id || call.callee_id == user_id
  end

  @doc """
  Get the other user ID in this call.
  """
  def other_user_id(call, user_id) do
    cond do
      call.caller_id == user_id -> call.callee_id
      call.callee_id == user_id -> call.caller_id
      true -> nil
    end
  end

  ## Private Functions

  defp validate_different_users(changeset) do
    caller_id = get_field(changeset, :caller_id)
    callee_id = get_field(changeset, :callee_id)

    if caller_id && callee_id && caller_id == callee_id do
      add_error(changeset, :callee_id, "cannot call yourself")
    else
      changeset
    end
  end

  defp calculate_duration_if_ended(changeset) do
    status = get_change(changeset, :status)
    started_at = get_field(changeset, :started_at)
    ended_at = get_change(changeset, :ended_at)

    if status == "ended" && started_at && ended_at do
      duration = DateTime.diff(ended_at, started_at, :second)
      put_change(changeset, :duration_seconds, max(0, duration))
    else
      changeset
    end
  end
end
