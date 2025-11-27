defmodule WemachatApiWeb.StatusController do
  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.Statuses
  alias WemachatApiWeb.Plugs.FirebaseAuth

  # All status routes require authentication
  plug FirebaseAuth

  @doc """
  GET /api/v1/statuses
  Get all status groups (authenticated users only).
  Returns statuses from other users, grouped by user.
  """
  def index(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    status_groups = Statuses.list_all_statuses(user_id, page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      statusGroups: Enum.map(status_groups, &format_status_group/1),
      status_groups: Enum.map(status_groups, &format_status_group/1),
      page: page,
      per_page: per_page
    })
  end

  @doc """
  GET /api/v1/statuses/me
  Get current user's statuses (authenticated).
  """
  def my_statuses(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    statuses = Statuses.list_user_statuses(user_id, page: page, per_page: per_page)
    enriched_statuses = Statuses.enrich_statuses_with_user_info(statuses)

    conn
    |> put_status(:ok)
    |> json(%{
      statuses: Enum.map(enriched_statuses, &format_status/1),
      page: page,
      per_page: per_page
    })
  end

  @doc """
  GET /api/v1/statuses/user/:id
  Get statuses for a specific user (authenticated).
  """
  def user_statuses(conn, %{"id" => target_user_id} = params) do
    viewer_id = FirebaseAuth.current_user_id(conn)
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    statuses = Statuses.list_user_statuses(target_user_id, page: page, per_page: per_page)

    # Filter out statuses that the viewer cannot see
    visible_statuses =
      statuses
      |> Enum.filter(fn status ->
        WemachatDatabase.Schemas.Status.visible_to_user?(status, viewer_id)
      end)
      |> Statuses.enrich_statuses_with_user_info()

    conn
    |> put_status(:ok)
    |> json(%{
      statuses: Enum.map(visible_statuses, &format_status/1),
      page: page,
      per_page: per_page
    })
  end

  @doc """
  POST /api/v1/statuses
  Create a new status (authenticated).
  """
  def create(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)

    # Transform camelCase params to snake_case
    transformed_params = transform_status_params(params, user_id)

    case Statuses.create_status(transformed_params) do
      {:ok, status} ->
        enriched_status = Statuses.enrich_statuses_with_user_info(status)

        conn
        |> put_status(:created)
        |> json(format_status(enriched_status))

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to create status", details: format_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/statuses/:id
  Delete a status (authenticated, owner only).
  """
  def delete(conn, %{"id" => status_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Statuses.delete_status(status_id, user_id) do
      {:ok, _status} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Status deleted successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Status not found or expired"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You can only delete your own statuses"})

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to delete status"})
    end
  end

  @doc """
  POST /api/v1/statuses/:id/view
  Record a status view (authenticated).
  """
  def view(conn, %{"id" => status_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Statuses.view_status(status_id, user_id) do
      {:ok, _view} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "View recorded successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Status not found or expired"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You don't have permission to view this status"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to record view", details: format_errors(changeset)})
    end
  end

  @doc """
  POST /api/v1/statuses/:id/like
  Like a status (authenticated).
  """
  def like(conn, %{"id" => status_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Statuses.like_status(status_id, user_id) do
      {:ok, _like} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Status liked successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Status not found or expired"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You don't have permission to like this status"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to like status", details: format_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/statuses/:id/unlike
  Unlike a status (authenticated).
  """
  def unlike(conn, %{"id" => status_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Statuses.unlike_status(status_id, user_id) do
      {:ok, :deleted} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Status unliked successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Status was not liked"})

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to unlike status"})
    end
  end

  # Helper Functions

  # Transform camelCase params from frontend to snake_case for Ecto
  defp transform_status_params(params, user_id) do
    %{
      "user_id" => user_id,
      "content" => params["content"],
      "media_url" => params["mediaUrl"] || params["media_url"],
      "media_type" => params["mediaType"] || params["media_type"],
      "thumbnail_url" => params["thumbnailUrl"] || params["thumbnail_url"],
      "text_background" => params["textBackground"] || params["text_background"],
      "visibility" => params["visibility"] || "all",
      "visible_to" => params["visibleTo"] || params["visible_to"] || [],
      "hidden_from" => params["hiddenFrom"] || params["hidden_from"] || [],
      "duration_seconds" => params["durationSeconds"] || params["duration_seconds"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  defp format_status(status) do
    %{
      id: status.id,
      userId: status.user_id,
      user_id: status.user_id,
      userName: Map.get(status, :user_name),
      user_name: Map.get(status, :user_name),
      userAvatar: Map.get(status, :user_avatar),
      user_avatar: Map.get(status, :user_avatar),
      content: status.content,
      mediaUrl: status.media_url,
      media_url: status.media_url,
      mediaType: status.media_type,
      media_type: status.media_type,
      thumbnailUrl: status.thumbnail_url,
      thumbnail_url: status.thumbnail_url,
      textBackground: status.text_background,
      text_background: status.text_background,
      visibility: status.visibility,
      visibleTo: status.visible_to,
      visible_to: status.visible_to,
      hiddenFrom: status.hidden_from,
      hidden_from: status.hidden_from,
      durationSeconds: status.duration_seconds,
      duration_seconds: status.duration_seconds,
      viewsCount: status.views_count,
      views_count: status.views_count,
      likesCount: status.likes_count,
      likes_count: status.likes_count,
      giftsCount: status.gifts_count,
      gifts_count: status.gifts_count,
      isDeleted: status.is_deleted,
      is_deleted: status.is_deleted,
      expiresAt: status.expires_at,
      expires_at: status.expires_at,
      createdAt: status.inserted_at,
      created_at: status.inserted_at,
      updatedAt: status.updated_at,
      updated_at: status.updated_at
    }
  end

  defp format_status_group(group) do
    %{
      userId: group.user_id,
      user_id: group.user_id,
      userName: group.user_name,
      user_name: group.user_name,
      userAvatar: group.user_avatar,
      user_avatar: group.user_avatar,
      statusCount: group.status_count,
      status_count: group.status_count,
      latestStatusAt: group.latest_status_at,
      latest_status_at: group.latest_status_at,
      statuses: Enum.map(group.statuses, &format_status/1)
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp parse_int(nil, default), do: default
  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end
  defp parse_int(_, default), do: default
end
