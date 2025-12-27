defmodule WemachatApiWeb.VideoController do
  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.{Videos, Recommendations}
  alias WemachatApiWeb.Plugs.FirebaseAuth

  # Apply Firebase auth to protected routes
  plug FirebaseAuth
       when action not in [:index, :show, :feed, :discover, :search, :user_videos, :comments, :for_you]

  @doc """
  POST /api/v1/videos
  Create a video (auth required).
  """
  def create(conn, params) do
    # Transform camelCase params from Flutter to snake_case for Ecto
    transformed_params = transform_video_params(params)

    case Videos.create_video(transformed_params) do
      {:ok, video} ->
        conn
        |> put_status(:created)
        |> json(format_video(video))

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to create video", details: format_errors(changeset)})
    end
  end

  @doc """
  GET /api/v1/videos/:id
  Get a single video (only if not expired).
  """
  def show(conn, %{"id" => id}) do
    case Videos.get_video(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found or expired"})

      video ->
        # Increment view count
        Videos.increment_views(video)

        conn
        |> put_status(:ok)
        |> json(format_video(video))
    end
  end

  @doc """
  GET /api/v1/videos/feed
  Get feed of videos (TikTok-style, only non-expired).
  """
  def feed(conn, params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    videos = Videos.get_feed(page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      videos: Enum.map(videos, &format_video/1),
      page: page,
      per_page: per_page
    })
  end

  @doc """
  GET /api/v1/videos/discover
  Get discover feed (trending non-expired videos).
  """
  def discover(conn, params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    videos = Videos.get_discover_feed(page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      videos: Enum.map(videos, &format_video/1),
      page: page,
      per_page: per_page
    })
  end

  @doc """
  GET /api/v1/videos/for-you
  Get personalized "For You" feed with recommendations (requires auth).
  Uses exclusion-based filtering and admin boost controls.
  """
  def for_you(conn, params) do
    user_id = get_user_id_from_query_or_auth(conn, params)

    if user_id do
      page = parse_int(params["page"], 1)
      per_page = parse_int(params["per_page"], 20)
      include_old = parse_boolean(params["include_old"], true)

      videos = Recommendations.get_for_you_feed(user_id, page: page, per_page: per_page, include_old: include_old)

      conn
      |> put_status(:ok)
      |> json(%{
        videos: Enum.map(videos, &format_video/1),
        page: page,
        per_page: per_page
      })
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Authentication required or user_id parameter missing"})
    end
  end

  @doc """
  POST /api/v1/videos/:id/view
  Record that a user has viewed a video (auth required).
  """
  def record_view(conn, %{"id" => video_id} = params) do
    user_id = FirebaseAuth.current_user_id(conn)

    attrs = %{
      watch_duration_seconds: parse_int(params["watch_duration_seconds"], 0),
      completed: parse_boolean(params["completed"], false)
    }

    case Recommendations.record_video_view(user_id, video_id, attrs) do
      {:ok, _view} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "View recorded successfully"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to record view", details: format_errors(changeset)})
    end
  end

  @doc """
  GET /api/v1/videos/search?q=query
  Search videos by caption.
  """
  def search(conn, %{"q" => query} = params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    videos = Videos.search_videos(query, page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      videos: Enum.map(videos, &format_video/1),
      page: page,
      per_page: per_page,
      query: query
    })
  end

  def search(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing search query parameter 'q'"})
  end

  @doc """
  GET /api/v1/users/:user_id/videos
  Get videos from a specific user.
  """
  def user_videos(conn, %{"user_id" => user_id} = params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    videos = Videos.list_user_videos(user_id, page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      videos: Enum.map(videos, &format_video/1),
      page: page,
      per_page: per_page
    })
  end

  @doc """
  PUT /api/v1/videos/:id
  Update a video (auth required).
  """
  def update(conn, %{"id" => id} = params) do
    case Videos.get_video(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found or expired"})

      video ->
        case Videos.update_video(video, params) do
          {:ok, updated} ->
            conn
            |> put_status(:ok)
            |> json(format_video(updated))

          {:error, changeset} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "Failed to update video", details: format_errors(changeset)})
        end
    end
  end

  @doc """
  DELETE /api/v1/videos/:id
  Delete a video (auth required).
  """
  def delete(conn, %{"id" => id}) do
    case Videos.get_video(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found or expired"})

      video ->
        case Videos.delete_video(video) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{message: "Video deleted successfully"})

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to delete video"})
        end
    end
  end

  @doc """
  POST /api/v1/videos/:id/like
  Like a video (auth required).
  """
  def like(conn, %{"id" => video_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Videos.like_video(user_id, video_id) do
      {:ok, _video} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Successfully liked video"})

      {:error, :video_not_found_or_expired} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found or expired"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to like video", details: format_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/videos/:id/like
  Unlike a video (auth required).
  """
  def unlike(conn, %{"id" => video_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Videos.unlike_video(user_id, video_id) do
      {:ok, :not_liked} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Video was not liked"})

      {:ok, _video} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Successfully unliked video"})

      {:error, :video_not_found_or_expired} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found or expired"})

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to unlike video"})
    end
  end

  @doc """
  POST /api/v1/videos/:id/share
  Increment share count (auth required).
  """
  def share(conn, %{"id" => id}) do
    case Videos.get_video(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found or expired"})

      video ->
        case Videos.increment_shares(video) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{message: "Share recorded"})

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to record share"})
        end
    end
  end

  @doc """
  POST /api/v1/videos/:id/comments
  Create a comment on a video (auth required).
  """
  def create_comment(conn, %{"id" => video_id} = params) do
    user_id = FirebaseAuth.current_user_id(conn)

    attrs =
      params
      |> Map.put("video_id", video_id)
      |> Map.put("user_id", user_id)

    case Videos.create_comment(attrs) do
      {:ok, comment} ->
        conn
        |> put_status(:created)
        |> json(format_comment(comment))

      {:error, :video_not_found_or_expired} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found or expired"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to create comment", details: format_errors(changeset)})
    end
  end

  @doc """
  GET /api/v1/videos/:id/comments
  Get comments for a video.
  """
  def comments(conn, %{"id" => video_id} = params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    comments = Videos.get_video_comments(video_id, page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      comments: Enum.map(comments, &format_comment/1),
      page: page,
      per_page: per_page
    })
  end

  # Helper Functions

  # Transform camelCase params from Flutter to snake_case for Ecto
  # Also filters out fields that Ecto auto-generates (timestamps, counts)
  defp transform_video_params(params) do
    %{
      "user_id" => params["userId"] || params["user_id"],
      "user_name" => params["userName"] || params["user_name"],
      "user_image" => params["userImage"] || params["user_image"],
      "video_url" => params["videoUrl"] || params["video_url"],
      "thumbnail_url" => params["thumbnailUrl"] || params["thumbnail_url"],
      "caption" => params["caption"],
      "tags" => params["tags"] || [],
      "price" => params["price"] || 0.0,
      "is_multiple_images" => params["isMultipleImages"] || params["is_multiple_images"] || false,
      "image_urls" => params["imageUrls"] || params["image_urls"] || [],
      "is_boosted" => params["isBoosted"] || params["is_boosted"] || false,
      "boost_tier" => params["boostTier"] || params["boost_tier"] || "none",
      "super_boost" => params["superBoost"] || params["super_boost"] || false
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
    # Note: We don't include these fields as Ecto handles them automatically:
    # - createdAt/updatedAt (Ecto timestamps())
    # - counts (likesCount, commentsCount, etc. - schema defaults to 0)
  end

  defp format_video(video) do
    %{
      id: video.id,
      userId: video.user_id,
      user_id: video.user_id,
      userName: video.user_name,
      user_name: video.user_name,
      userImage: video.user_image,
      user_image: video.user_image,
      videoUrl: video.video_url,
      video_url: video.video_url,
      thumbnailUrl: video.thumbnail_url,
      thumbnail_url: video.thumbnail_url,
      caption: video.caption,
      tags: video.tags,
      views: video.views,
      likes: video.likes,
      comments: video.comments,
      shares: video.shares,
      isActive: video.is_active,
      is_active: video.is_active,
      isFeatured: video.is_featured,
      is_featured: video.is_featured,
      isBoosted: video.is_boosted,
      is_boosted: video.is_boosted,
      boostTier: video.boost_tier,
      boost_tier: video.boost_tier,
      superBoost: video.super_boost,
      super_boost: video.super_boost,
      price: video.price,
      isMultipleImages: video.is_multiple_images,
      is_multiple_images: video.is_multiple_images,
      imageUrls: video.image_urls,
      image_urls: video.image_urls,
      expiresAt: video.expires_at,
      expires_at: video.expires_at,
      createdAt: video.inserted_at,
      created_at: video.inserted_at,
      updatedAt: video.updated_at,
      updated_at: video.updated_at
    }
  end

  defp format_comment(comment) do
    %{
      id: comment.id,
      videoId: comment.video_id,
      video_id: comment.video_id,
      userId: comment.user_id,
      user_id: comment.user_id,
      commentText: comment.comment_text,
      comment_text: comment.comment_text,
      imageUrl: comment.image_url,
      image_url: comment.image_url,
      createdAt: comment.inserted_at,
      created_at: comment.inserted_at,
      updatedAt: comment.updated_at,
      updated_at: comment.updated_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(_, default), do: default

  defp parse_boolean(value, default) when is_binary(value) do
    case String.downcase(value) do
      "true" -> true
      "false" -> false
      "1" -> true
      "0" -> false
      _ -> default
    end
  end

  defp parse_boolean(value, _default) when is_boolean(value), do: value
  defp parse_boolean(_, default), do: default

  # Get user ID from query parameter or Firebase auth
  # This allows public endpoints to be personalized if user_id is provided
  defp get_user_id_from_query_or_auth(conn, params) do
    params["user_id"] || FirebaseAuth.current_user_id(conn)
  end
end
