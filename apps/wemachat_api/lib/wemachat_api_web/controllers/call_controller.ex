defmodule WemachatApiWeb.CallController do
  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.Calls
  alias WemachatApiWeb.Plugs.FirebaseAuth

  # Apply Firebase auth to all routes
  plug FirebaseAuth

  @doc """
  GET /api/v1/calls
  Get current user's call history.
  """
  def index(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    calls = Calls.list_user_calls(user_id, page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      calls: Enum.map(calls, &format_call/1),
      page: page,
      per_page: per_page
    })
  end

  @doc """
  GET /api/v1/calls/active
  Get current user's active calls (pending, ringing, or in progress).
  """
  def active(conn, _params) do
    user_id = FirebaseAuth.current_user_id(conn)
    calls = Calls.list_active_calls(user_id)

    conn
    |> put_status(:ok)
    |> json(%{
      calls: Enum.map(calls, &format_call/1)
    })
  end

  @doc """
  GET /api/v1/calls/missed
  Get current user's missed calls.
  """
  def missed(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    calls = Calls.list_missed_calls(user_id, page: page, per_page: per_page)
    count = Calls.count_missed_calls(user_id)

    conn
    |> put_status(:ok)
    |> json(%{
      calls: Enum.map(calls, &format_call/1),
      missed_count: count,
      page: page,
      per_page: per_page
    })
  end

  @doc """
  GET /api/v1/calls/stats
  Get current user's call statistics.
  """
  def stats(conn, _params) do
    user_id = FirebaseAuth.current_user_id(conn)
    stats = Calls.get_user_call_stats(user_id)

    conn
    |> put_status(:ok)
    |> json(stats)
  end

  @doc """
  GET /api/v1/calls/:id
  Get a specific call by ID.
  """
  def show(conn, %{"id" => call_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Calls.get_call(call_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Call not found"})

      call ->
        # Verify user is participant
        if call.caller_id == user_id || call.callee_id == user_id do
          conn
          |> put_status(:ok)
          |> json(format_call(call))
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "Unauthorized"})
        end
    end
  end

  @doc """
  DELETE /api/v1/calls/:id
  Delete a call from history (soft delete).
  """
  def delete(conn, %{"id" => call_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Calls.delete_call(call_id, user_id) do
      {:ok, _call} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Call deleted successfully"})

      {:error, :call_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Call not found"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Unauthorized"})

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to delete call"})
    end
  end

  ## Private Functions

  defp format_call(call) do
    %{
      id: call.id,
      callerId: call.caller_id,
      caller_id: call.caller_id,
      calleeId: call.callee_id,
      callee_id: call.callee_id,
      callType: call.call_type,
      call_type: call.call_type,
      status: call.status,
      startedAt: call.started_at,
      started_at: call.started_at,
      endedAt: call.ended_at,
      ended_at: call.ended_at,
      durationSeconds: call.duration_seconds,
      duration_seconds: call.duration_seconds,
      isDeleted: call.is_deleted,
      is_deleted: call.is_deleted,
      createdAt: call.inserted_at,
      created_at: call.inserted_at,
      updatedAt: call.updated_at,
      updated_at: call.updated_at
    }
  end

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(_, default), do: default
end
