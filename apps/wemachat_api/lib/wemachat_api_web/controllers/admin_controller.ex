defmodule WemachatApiWeb.AdminController do
  @moduledoc """
  Admin controller for content moderation and recommendation system management.
  All endpoints require admin/moderator authentication.
  """

  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.Recommendations
  alias WemachatApiWeb.Plugs.FirebaseAuth

  # All admin routes require authentication
  # TODO: Add AdminOnly plug when implemented
  plug FirebaseAuth

  ## VIDEO MODERATION ENDPOINTS

  @doc """
  PUT /api/v1/admin/videos/:id/boost
  Set admin boost score for a video (0-100).
  """
  def set_video_boost(conn, %{"id" => video_id, "boost_score" => boost_score}) do
    case parse_boost_score(boost_score) do
      {:ok, score} ->
        case Recommendations.set_admin_boost(video_id, score) do
          {:ok, video} ->
            conn
            |> put_status(:ok)
            |> json(%{
              message: "Video boost updated successfully",
              video_id: video.id,
              admin_boost_score: video.admin_boost_score
            })

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Video not found"})

          {:error, changeset} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "Failed to update boost score", details: format_errors(changeset)})
        end

      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})
    end
  end

  @doc """
  PUT /api/v1/admin/videos/:id/pin
  Pin a video (makes it appear first in all feeds).
  """
  def pin_video(conn, %{"id" => video_id}) do
    case Recommendations.pin_video(video_id) do
      {:ok, _video} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Video pinned successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to pin video", details: format_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/admin/videos/:id/pin
  Unpin a video.
  """
  def unpin_video(conn, %{"id" => video_id}) do
    case Recommendations.unpin_video(video_id) do
      {:ok, _video} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Video unpinned successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to unpin video", details: format_errors(changeset)})
    end
  end

  @doc """
  PUT /api/v1/admin/videos/:id/visibility
  Set video visibility level (public, limited, hidden).
  """
  def set_video_visibility(conn, %{"id" => video_id, "visibility_level" => level}) do
    if level in ["public", "limited", "hidden"] do
      case Recommendations.set_visibility(video_id, level) do
        {:ok, _video} ->
          conn
          |> put_status(:ok)
          |> json(%{message: "Video visibility updated successfully"})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Video not found"})

        {:error, changeset} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Failed to update visibility", details: format_errors(changeset)})
      end
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Invalid visibility level. Must be: public, limited, or hidden"})
    end
  end

  @doc """
  PUT /api/v1/admin/videos/:id/geo-target
  Set geo-targeting for a video.
  """
  def set_video_geo_targeting(conn, %{"id" => video_id} = params) do
    opts = []
    opts = if params["counties"], do: Keyword.put(opts, :counties, params["counties"]), else: opts
    opts = if params["constituencies"], do: Keyword.put(opts, :constituencies, params["constituencies"]), else: opts
    opts = if params["wards"], do: Keyword.put(opts, :wards, params["wards"]), else: opts

    case Recommendations.set_geo_targeting(video_id, opts) do
      {:ok, _video} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Geo-targeting updated successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to update geo-targeting", details: format_errors(changeset)})
    end
  end

  ## USER MODERATION ENDPOINTS

  @doc """
  PUT /api/v1/admin/users/:id/mute
  Mute a user (hide all their content from recommendations).
  """
  def mute_user(conn, %{"id" => user_id}) do
    case Recommendations.mute_user(user_id) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "User muted successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to mute user", details: format_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/admin/users/:id/mute
  Unmute a user.
  """
  def unmute_user(conn, %{"id" => user_id}) do
    case Recommendations.unmute_user(user_id) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "User unmuted successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to unmute user", details: format_errors(changeset)})
    end
  end

  @doc """
  PUT /api/v1/admin/users/:id/shadowban
  Shadowban a user (drastically reduce their reach without notification).
  """
  def shadowban_user(conn, %{"id" => user_id}) do
    case Recommendations.shadowban_user(user_id) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "User shadowbanned successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to shadowban user", details: format_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/admin/users/:id/shadowban
  Remove shadowban from a user.
  """
  def unshadowban_user(conn, %{"id" => user_id}) do
    case Recommendations.unshadowban_user(user_id) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Shadowban removed successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to remove shadowban", details: format_errors(changeset)})
    end
  end

  @doc """
  PUT /api/v1/admin/users/:id/reach-multiplier
  Set user's reach multiplier (0.0 to 2.0).
  """
  def set_reach_multiplier(conn, %{"id" => user_id, "multiplier" => multiplier}) do
    case parse_float(multiplier) do
      {:ok, value} when value >= 0.0 and value <= 2.0 ->
        case Recommendations.set_reach_multiplier(user_id, value) do
          {:ok, _user} ->
            conn
            |> put_status(:ok)
            |> json(%{message: "Reach multiplier updated successfully"})

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "User not found"})

          {:error, changeset} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "Failed to update reach multiplier", details: format_errors(changeset)})
        end

      {:ok, _} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Reach multiplier must be between 0.0 and 2.0"})

      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})
    end
  end

  @doc """
  PUT /api/v1/admin/users/:id/creator-content-type
  Set user's creator content type.
  """
  def set_creator_content_type(conn, %{"id" => user_id, "content_type" => content_type}) do
    valid_types = [
      "comedy", "music", "education", "news", "lifestyle",
      "sports", "technology", "fashion", "food", "travel",
      "entertainment", "business", "health", "politics", "other"
    ]

    if content_type in valid_types do
      case Recommendations.set_creator_content_type(user_id, content_type) do
        {:ok, _user} ->
          conn
          |> put_status(:ok)
          |> json(%{message: "Creator content type updated successfully"})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "User not found"})

        {:error, changeset} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Failed to update content type", details: format_errors(changeset)})
      end
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Invalid content type", valid_types: valid_types})
    end
  end

  @doc """
  PUT /api/v1/admin/users/:id/interest-type
  Set user's interest type (what they watch).
  """
  def set_interest_type(conn, %{"id" => user_id, "content_type" => content_type}) do
    valid_types = [
      "comedy", "music", "education", "news", "lifestyle",
      "sports", "technology", "fashion", "food", "travel",
      "entertainment", "business", "health", "politics", "other"
    ]

    if content_type in valid_types do
      case Recommendations.set_interest_type(user_id, content_type) do
        {:ok, _user} ->
          conn
          |> put_status(:ok)
          |> json(%{message: "Interest type updated successfully"})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "User not found"})

        {:error, changeset} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Failed to update interest type", details: format_errors(changeset)})
      end
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Invalid content type", valid_types: valid_types})
    end
  end

  ## SILENT PUSH SYSTEM ENDPOINTS

  @doc """
  PUT /api/v1/admin/videos/:id/push-to-all
  Activate silent push to all users for a video.
  No notifications sent - video just gets priority in feeds.
  """
  def activate_push_to_all(conn, %{"id" => video_id}) do
    case Recommendations.activate_push_to_all(video_id) do
      {:ok, _video} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Silent push to all activated successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to activate push", details: format_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/admin/videos/:id/push-to-all
  Deactivate silent push to all for a video.
  """
  def deactivate_push_to_all(conn, %{"id" => video_id}) do
    case Recommendations.deactivate_push_to_all(video_id) do
      {:ok, _video} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Silent push to all deactivated successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to deactivate push", details: format_errors(changeset)})
    end
  end

  @doc """
  PUT /api/v1/admin/videos/:id/push-targeting
  Set location-based silent push for a video.
  Push precedence: push_to_all > push_to_counties > push_to_constituencies > push_to_wards
  """
  def set_push_targeting(conn, %{"id" => video_id} = params) do
    opts = []
    opts = if params["counties"], do: Keyword.put(opts, :counties, params["counties"]), else: opts
    opts = if params["constituencies"], do: Keyword.put(opts, :constituencies, params["constituencies"]), else: opts
    opts = if params["wards"], do: Keyword.put(opts, :wards, params["wards"]), else: opts

    case Recommendations.set_push_targeting(video_id, opts) do
      {:ok, _video} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Silent push targeting updated successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to update push targeting", details: format_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/admin/videos/:id/push
  Clear all silent push settings for a video.
  """
  def clear_all_push(conn, %{"id" => video_id}) do
    case Recommendations.clear_all_push(video_id) do
      {:ok, _video} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "All silent push settings cleared successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to clear push settings", details: format_errors(changeset)})
    end
  end

  ## HELPER FUNCTIONS

  defp parse_boost_score(value) when is_integer(value) and value >= 0 and value <= 100, do: {:ok, value}
  defp parse_boost_score(value) when is_binary(value) do
    case Integer.parse(value) do
      {score, _} when score >= 0 and score <= 100 -> {:ok, score}
      {_, _} -> {:error, "Boost score must be between 0 and 100"}
      :error -> {:error, "Invalid boost score format"}
    end
  end
  defp parse_boost_score(_), do: {:error, "Boost score must be between 0 and 100"}

  defp parse_float(value) when is_float(value), do: {:ok, value}
  defp parse_float(value) when is_integer(value), do: {:ok, value * 1.0}
  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> {:ok, float}
      :error -> {:error, "Invalid number format"}
    end
  end
  defp parse_float(_), do: {:error, "Invalid number format"}

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
