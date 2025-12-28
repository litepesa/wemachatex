defmodule WemachatApiWeb.PostController do
  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.Moments
  alias WemachatApiWeb.Plugs.FirebaseAuth

  # Apply Firebase auth to protected routes
  plug FirebaseAuth
       when action not in [:index, :show, :discover, :search, :user_posts, :comments]

  @doc """
  POST /api/v1/posts
  Create a post (auth required).
  """
  def create(conn, params) do
    require Logger

    user_id = FirebaseAuth.current_user_id(conn)
    Logger.info("[POST CREATE] User ID: #{user_id}")
    Logger.info("[POST CREATE] Raw params: #{inspect(params)}")

    # Transform camelCase params and add user_id
    attrs = transform_post_params(Map.put(params, "user_id", user_id))
    Logger.info("[POST CREATE] Transformed attrs: #{inspect(attrs)}")

    case Moments.create_post(attrs) do
      {:ok, post} ->
        Logger.info("[POST CREATE] Success! Post ID: #{post.id}")
        conn
        |> put_status(:created)
        |> json(format_post(post, user_id))

      {:error, :user_not_found} ->
        Logger.error("[POST CREATE] User not found: #{user_id}")
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found. Please sync your profile."})

      {:error, :user_name_missing} ->
        Logger.error("[POST CREATE] User has no name: #{user_id}")
        conn
        |> put_status(:bad_request)
        |> json(%{error: "User profile incomplete. Please update your name in settings."})

      {:error, changeset} ->
        Logger.error("[POST CREATE] Failed! Changeset errors: #{inspect(changeset.errors)}")
        Logger.error("[POST CREATE] Changeset: #{inspect(changeset)}")
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to create post", details: format_errors(changeset)})
    end
  end

  @doc """
  GET /api/v1/posts/:id
  Get a single post.
  """
  def show(conn, %{"id" => id}) do
    case Moments.get_post(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Post not found"})

      post ->
        conn
        |> put_status(:ok)
        |> json(format_post(post))
    end
  end

  @doc """
  GET /api/v1/posts/feed
  Get feed for authenticated user (posts from contacts + own posts).
  """
  def feed(conn, params) do
    require Logger

    user_id = FirebaseAuth.current_user_id(conn)
    Logger.info("[POSTS FEED] User ID: #{user_id}")

    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)
    Logger.info("[POSTS FEED] Page: #{page}, Per page: #{per_page}")

    try do
      posts = Moments.get_feed(user_id, page: page, per_page: per_page)
      Logger.info("[POSTS FEED] Found #{length(posts)} posts for user #{user_id}")

      conn
      |> put_status(:ok)
      |> json(%{
        posts: Enum.map(posts, &format_post(&1, user_id)),
        page: page,
        per_page: per_page
      })
    rescue
      e ->
        Logger.error("[POSTS FEED] Error: #{inspect(e)}")
        Logger.error("[POSTS FEED] Stacktrace: #{inspect(__STACKTRACE__)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to load feed", details: inspect(e)})
    end
  end

  @doc """
  GET /api/v1/posts/discover
  Get discover feed (trending public posts).
  """
  def discover(conn, params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    posts = Moments.get_discover_feed(page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      posts: Enum.map(posts, &format_post/1),
      page: page,
      per_page: per_page
    })
  end

  @doc """
  GET /api/v1/posts/search?q=query
  Search posts by content.
  """
  def search(conn, %{"q" => query} = params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    posts = Moments.search_posts(query, page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      posts: Enum.map(posts, &format_post/1),
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
  GET /api/v1/users/:user_id/posts
  Get posts from a specific user.
  """
  def user_posts(conn, %{"user_id" => user_id} = params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    posts = Moments.list_user_posts(user_id, page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      posts: Enum.map(posts, &format_post/1),
      page: page,
      per_page: per_page
    })
  end

  @doc """
  PUT /api/v1/posts/:id
  Update a post (auth required, owner only).
  """
  def update(conn, %{"id" => id} = params) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Moments.get_post(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Post not found"})

      post ->
        if post.user_id == user_id do
          case Moments.update_post(post, params) do
            {:ok, updated} ->
              conn
              |> put_status(:ok)
              |> json(format_post(updated))

            {:error, changeset} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Failed to update post", details: format_errors(changeset)})
          end
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "You can only update your own posts"})
        end
    end
  end

  @doc """
  DELETE /api/v1/posts/:id
  Delete a post (auth required, owner only).
  """
  def delete(conn, %{"id" => id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Moments.get_post(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Post not found"})

      post ->
        if post.user_id == user_id do
          case Moments.delete_post(post) do
            {:ok, _} ->
              conn
              |> put_status(:ok)
              |> json(%{message: "Post deleted successfully"})

            {:error, _} ->
              conn
              |> put_status(:internal_server_error)
              |> json(%{error: "Failed to delete post"})
          end
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "You can only delete your own posts"})
        end
    end
  end

  @doc """
  POST /api/v1/posts/:id/like
  Like a post (auth required).
  """
  def like(conn, %{"id" => post_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Moments.like_post(user_id, post_id) do
      {:ok, _} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Successfully liked post"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to like post", details: format_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/posts/:id/like
  Unlike a post (auth required).
  """
  def unlike(conn, %{"id" => post_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Moments.unlike_post(user_id, post_id) do
      {:ok, :not_liked} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Post was not liked"})

      {:ok, :unliked} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Successfully unliked post"})

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to unlike post"})
    end
  end

  @doc """
  POST /api/v1/posts/:id/comments
  Create a comment on a post (auth required).
  """
  def create_comment(conn, %{"id" => post_id} = params) do
    user_id = FirebaseAuth.current_user_id(conn)

    # Transform camelCase → snake_case for comment fields
    attrs = %{
      "post_id" => post_id,
      "user_id" => user_id,
      "comment_text" => params["commentText"] || params["comment_text"],
      "reply_to_user_id" => params["replyToUserId"] || params["reply_to_user_id"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})

    case Moments.create_comment(attrs) do
      {:ok, comment} ->
        conn
        |> put_status(:created)
        |> json(format_comment(comment))

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to create comment", details: format_errors(changeset)})
    end
  end

  @doc """
  GET /api/v1/posts/:id/comments
  Get comments for a post.
  """
  def comments(conn, %{"id" => post_id} = params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    comments = Moments.list_post_comments(post_id, page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      comments: Enum.map(comments, &format_comment/1),
      page: page,
      per_page: per_page
    })
  end

  ## Private Functions

  defp transform_post_params(params) do
    %{
      "user_id" => params["userId"] || params["user_id"],
      "content_text" => params["contentText"] || params["content_text"],
      "media_urls" => params["mediaUrls"] || params["media_urls"] || [],
      "media_type" => params["mediaType"] || params["media_type"],
      "visibility" => params["visibility"] || "public",
      "visible_to" => params["visibleTo"] || params["visible_to"] || [],
      "hidden_from" => params["hiddenFrom"] || params["hidden_from"] || [],
      "location" => params["location"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  defp format_post(post, current_user_id \\ nil) do
    %{
      # Basic fields (dual format for compatibility)
      id: post.id,
      userId: post.user_id,
      user_id: post.user_id,
      userName: post.user_name,
      user_name: post.user_name,
      userImage: post.user_image,
      user_image: post.user_image,
      contentText: post.content_text,
      content_text: post.content_text,
      mediaUrls: post.media_urls,
      media_urls: post.media_urls,
      mediaType: post.media_type,
      media_type: post.media_type,
      visibility: post.visibility,
      location: post.location,
      # Privacy fields (dual format)
      visibleTo: post.visible_to || [],
      visible_to: post.visible_to || [],
      hiddenFrom: post.hidden_from || [],
      hidden_from: post.hidden_from || [],
      # Counts
      likesCount: post.likes_count,
      likes_count: post.likes_count,
      commentsCount: post.comments_count,
      comments_count: post.comments_count,
      sharesCount: post.shares_count,
      shares_count: post.shares_count,
      # Computed fields (only if current_user_id provided)
      isLikedByMe:
        if(current_user_id,
          do: Moments.is_liked_by_user?(post.id, current_user_id),
          else: false
        ),
      is_liked_by_me:
        if(current_user_id,
          do: Moments.is_liked_by_user?(post.id, current_user_id),
          else: false
        ),
      isMutualContact:
        if(current_user_id && post.user_id != current_user_id,
          do: Moments.is_mutual_contact?(current_user_id, post.user_id),
          else: false
        ),
      is_mutual_contact:
        if(current_user_id && post.user_id != current_user_id,
          do: Moments.is_mutual_contact?(current_user_id, post.user_id),
          else: false
        ),
      # Timestamps
      createdAt: post.inserted_at,
      created_at: post.inserted_at,
      updatedAt: post.updated_at,
      updated_at: post.updated_at,
      isActive: post.is_active,
      is_active: post.is_active
    }
  end

  defp format_comment(comment) do
    %{
      id: comment.id,
      postId: comment.post_id,
      post_id: comment.post_id,
      userId: comment.user_id,
      user_id: comment.user_id,
      commentText: comment.comment_text,
      comment_text: comment.comment_text,
      replyToUserId: comment.reply_to_user_id,
      reply_to_user_id: comment.reply_to_user_id,
      mediaUrl: comment.media_url,
      media_url: comment.media_url,
      isDeleted: comment.is_deleted,
      is_deleted: comment.is_deleted,
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
end
