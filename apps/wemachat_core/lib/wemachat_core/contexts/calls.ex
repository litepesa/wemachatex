defmodule WemachatCore.Contexts.Calls do
  @moduledoc """
  The Calls context.
  Handles all business logic for voice/video calls between users.
  """

  import Ecto.Query, warn: false
  alias WemachatDatabase.Repo
  alias WemachatDatabase.Schemas.Call

  ## CALL MANAGEMENT

  @doc """
  Initiate a new call.
  Creates a call in "pending" status.
  """
  def initiate_call(caller_id, callee_id, call_type) when call_type in ["audio", "video"] do
    %Call{}
    |> Call.create_changeset(%{
      caller_id: caller_id,
      callee_id: callee_id,
      call_type: call_type,
      status: "pending"
    })
    |> Repo.insert()
  end

  @doc """
  Update call status to "ringing" when the callee's device is notified.
  """
  def mark_call_ringing(call_id) do
    case get_call(call_id) do
      nil ->
        {:error, :call_not_found}

      call ->
        call
        |> Call.update_changeset(%{status: "ringing"})
        |> Repo.update()
    end
  end

  @doc """
  Start a call (move to "active" status).
  Records the started_at timestamp.
  """
  def start_call(call_id) do
    case get_call(call_id) do
      nil ->
        {:error, :call_not_found}

      call ->
        call
        |> Call.update_changeset(%{
          status: "active",
          started_at: DateTime.utc_now()
        })
        |> Repo.update()
    end
  end

  @doc """
  End a call.
  Records the ended_at timestamp and calculates duration.
  """
  def end_call(call_id) do
    case get_call(call_id) do
      nil ->
        {:error, :call_not_found}

      call ->
        call
        |> Call.update_changeset(%{
          status: "ended",
          ended_at: DateTime.utc_now()
        })
        |> Repo.update()
    end
  end

  @doc """
  Reject a call.
  Callee declined the incoming call.
  """
  def reject_call(call_id) do
    case get_call(call_id) do
      nil ->
        {:error, :call_not_found}

      call ->
        call
        |> Call.update_changeset(%{status: "rejected"})
        |> Repo.update()
    end
  end

  @doc """
  Cancel a call.
  Caller cancelled before callee answered.
  """
  def cancel_call(call_id) do
    case get_call(call_id) do
      nil ->
        {:error, :call_not_found}

      call ->
        call
        |> Call.update_changeset(%{status: "cancelled"})
        |> Repo.update()
    end
  end

  @doc """
  Mark a call as missed.
  Callee didn't answer within timeout period.
  """
  def mark_call_missed(call_id) do
    case get_call(call_id) do
      nil ->
        {:error, :call_not_found}

      call ->
        call
        |> Call.update_changeset(%{status: "missed"})
        |> Repo.update()
    end
  end

  @doc """
  Soft delete a call from history.
  """
  def delete_call(call_id, user_id) do
    case get_call(call_id) do
      nil ->
        {:error, :call_not_found}

      call ->
        if Call.participant?(call, user_id) do
          call
          |> Call.delete_changeset()
          |> Repo.update()
        else
          {:error, :unauthorized}
        end
    end
  end

  ## CALL QUERIES

  @doc """
  Get a call by ID.
  """
  def get_call(id), do: Repo.get(Call, id)

  @doc """
  Get call history for a user (calls they made or received).
  """
  def list_user_calls(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    Call
    |> where([c], (c.caller_id == ^user_id or c.callee_id == ^user_id) and c.is_deleted == false)
    |> order_by([c], desc: c.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Get active/ongoing calls for a user.
  """
  def list_active_calls(user_id) do
    Call
    |> where([c], (c.caller_id == ^user_id or c.callee_id == ^user_id))
    |> where([c], c.status in ["pending", "ringing", "active"])
    |> where([c], c.is_deleted == false)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Get missed calls for a user (calls they didn't answer).
  """
  def list_missed_calls(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    Call
    |> where([c], c.callee_id == ^user_id and c.status == "missed" and c.is_deleted == false)
    |> order_by([c], desc: c.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Count missed calls for a user.
  """
  def count_missed_calls(user_id) do
    Call
    |> where([c], c.callee_id == ^user_id and c.status == "missed" and c.is_deleted == false)
    |> Repo.aggregate(:count)
  end

  ## STATISTICS

  @doc """
  Get call statistics for a user.
  """
  def get_user_call_stats(user_id) do
    calls = Call
    |> where([c], (c.caller_id == ^user_id or c.callee_id == ^user_id) and c.is_deleted == false)
    |> Repo.all()

    total_calls = length(calls)
    outgoing_calls = Enum.count(calls, &(&1.caller_id == user_id))
    incoming_calls = Enum.count(calls, &(&1.callee_id == user_id))
    missed_calls = Enum.count(calls, &(&1.callee_id == user_id && &1.status == "missed"))
    total_duration = calls |> Enum.map(& &1.duration_seconds) |> Enum.sum()

    %{
      total_calls: total_calls,
      outgoing_calls: outgoing_calls,
      incoming_calls: incoming_calls,
      missed_calls: missed_calls,
      total_duration_seconds: total_duration,
      total_duration_minutes: Float.round(total_duration / 60, 1)
    }
  end
end
