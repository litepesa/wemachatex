defmodule WemachatApiWeb.ChannelPostController do
  @moduledoc """
  Controller for channel posts (create, view, like, unlock premium).
  """
  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.Channels
  alias WemachatApiWeb.Plugs.FirebaseAuth

  plug FirebaseAuth

  ## POST CRUD

  @doc """
  GET /api/v1/channels/:channel_id/posts
  List posts in a channel.
  """
  def index(conn, %{"channel_id" => channel_id} = params) do
    opts = [
      page: String.to_integer(params["page"] || "1"),
      per_page: String.to_integer(params["per_page"] || "20")
    ]

    posts = Channels.list_channel_posts(channel_id, opts)
    user_id = FirebaseAuth.current_user_id(conn)

    # Check unlock status for premium posts
    formatted_posts =
      Enum.map(posts, fn post ->
        is_unlocked =
          if post.is_premium do
            Channels.has_unlocked_post?(post.id, user_id)
          else
            true
          end

        format_post(post, is_unlocked)
      end)

    conn
    |> put_status(:ok)
    |> json(%{posts: formatted_posts})
  end

  @doc """
  GET /api/v1/posts/:id
  Get a single post by ID.
  """
  def show(conn, %{"id" => id}) do
    case Channels.get_post(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Post not found"})

      post ->
        user_id = FirebaseAuth.current_user_id(conn)

        # Increment views
        Channels.increment_post_views(id)

        # Check unlock status
        is_unlocked =
          if post.is_premium do
            Channels.has_unlocked_post?(id, user_id)
          else
            true
          end

        conn
        |> put_status(:ok)
        |> json(%{post: format_post(post, is_unlocked)})
    end
  end

  @doc """
  POST /api/v1/posts
  Create a new post in a channel.
  Body: {channelId, contentType, text?, mediaUrl?, mediaUrls?, isPremium?, priceCoins?, ...}
  """
  def create(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)
    channel_id = params["channelId"] || params["channel_id"]

    # Check if user can post in this channel
    if Channels.can_post_in_channel?(channel_id, user_id) do
      attrs = %{
        "channel_id" => channel_id,
        "author_id" => user_id,
        "content_type" => params["contentType"] || params["content_type"] || "text",
        "text" => params["text"],
        "media_url" => params["mediaUrl"] || params["media_url"],
        "media_urls" => params["mediaUrls"] || params["media_urls"],
        "media_thumbnail_url" => params["mediaThumbnailUrl"] || params["media_thumbnail_url"],
        "media_size_bytes" => params["mediaSizeBytes"] || params["media_size_bytes"],
        "media_duration_seconds" =>
          params["mediaDurationSeconds"] || params["media_duration_seconds"],
        "is_premium" => params["isPremium"] || params["is_premium"] || false,
        "price_coins" => params["priceCoins"] || params["price_coins"],
        "preview_duration_seconds" =>
          params["previewDurationSeconds"] || params["preview_duration_seconds"]
      }

      case Channels.create_post(attrs) do
        {:ok, post} ->
          conn
          |> put_status(:created)
          |> json(%{post: format_post(post, true)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to create post", errors: format_errors(changeset)})
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "You don't have permission to post in this channel"})
    end
  end

  @doc """
  PUT /api/v1/posts/:id
  Update a post (text only, author/owner/admin/moderator only).
  Body: {text}
  """
  def update(conn, %{"id" => id} = params) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Channels.get_post(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Post not found"})

      post ->
        # Check if user can update (author, channel owner, or channel member)
        can_update =
          post.author_id == user_id or
            Channels.is_channel_owner?(post.channel_id, user_id) or
            Channels.is_channel_member?(post.channel_id, user_id)

        if can_update do
          case Channels.update_post(post, %{"text" => params["text"]}) do
            {:ok, updated_post} ->
              conn
              |> put_status(:ok)
              |> json(%{post: format_post(updated_post, true)})

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Failed to update post", errors: format_errors(changeset)})
          end
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "You don't have permission to update this post"})
        end
    end
  end

  @doc """
  DELETE /api/v1/posts/:id
  Delete a post (author/owner/admin/moderator only).
  """
  def delete(conn, %{"id" => id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Channels.get_post(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Post not found"})

      post ->
        # Check if user can delete
        can_delete =
          post.author_id == user_id or
            Channels.is_channel_owner?(post.channel_id, user_id) or
            Channels.is_channel_member?(post.channel_id, user_id)

        if can_delete do
          case Channels.delete_post(post) do
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
          |> json(%{error: "You don't have permission to delete this post"})
        end
    end
  end

  ## POST INTERACTIONS

  @doc """
  POST /api/v1/posts/:id/like
  Like a post.
  """
  def like(conn, %{"id" => id}) do
    case Channels.like_post(id) do
      {:ok, post} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Post liked",
          likes: post.likes
        })

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to like post"})
    end
  end

  @doc """
  DELETE /api/v1/posts/:id/like
  Unlike a post.
  """
  def unlike(conn, %{"id" => id}) do
    case Channels.unlike_post(id) do
      {:ok, post} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Post unliked",
          likes: post.likes
        })

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to unlike post"})
    end
  end

  ## PREMIUM CONTENT

  @doc """
  POST /api/v1/posts/:id/unlock
  Unlock a premium post with coins.
  """
  def unlock(conn, %{"id" => id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Channels.unlock_premium_post(id, user_id) do
      {:ok, unlock} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Post unlocked successfully",
          unlock: format_unlock(unlock)
        })

      {:error, :post_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Post not found"})

      {:error, :not_premium_post} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "This is not a premium post"})

      {:error, :already_unlocked} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Post already unlocked"})

      {:error, :insufficient_balance} ->
        conn
        |> put_status(:payment_required)
        |> json(%{error: "Insufficient coins to unlock post"})

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to unlock post"})
    end
  end

  ## PRIVATE HELPERS

  defp format_post(post, is_unlocked) do
    base_format = %{
      id: post.id,
      channelId: post.channel_id,
      channel_id: post.channel_id,
      authorId: post.author_id,
      author_id: post.author_id,
      contentType: post.content_type,
      content_type: post.content_type,
      text: post.text,
      mediaThumbnailUrl: post.media_thumbnail_url,
      media_thumbnail_url: post.media_thumbnail_url,
      mediaSizeBytes: post.media_size_bytes,
      media_size_bytes: post.media_size_bytes,
      mediaDurationSeconds: post.media_duration_seconds,
      media_duration_seconds: post.media_duration_seconds,
      isPremium: post.is_premium,
      is_premium: post.is_premium,
      priceCoins: post.price_coins,
      price_coins: post.price_coins,
      previewDurationSeconds: post.preview_duration_seconds,
      preview_duration_seconds: post.preview_duration_seconds,
      likes: post.likes,
      commentsCount: post.comments_count,
      comments_count: post.comments_count,
      views: post.views,
      unlocks: post.unlocks,
      createdAt: post.inserted_at,
      created_at: post.inserted_at,
      updatedAt: post.updated_at,
      updated_at: post.updated_at,
      isUnlocked: is_unlocked,
      is_unlocked: is_unlocked
    }

    # Only include full media URLs if unlocked (or not premium)
    if is_unlocked do
      Map.merge(base_format, %{
        mediaUrl: post.media_url,
        media_url: post.media_url,
        mediaUrls: post.media_urls,
        media_urls: post.media_urls
      })
    else
      base_format
    end
  end

  defp format_unlock(unlock) do
    %{
      id: unlock.id,
      postId: unlock.post_id,
      post_id: unlock.post_id,
      userId: unlock.user_id,
      user_id: unlock.user_id,
      coinsPaid: unlock.coins_paid,
      coins_paid: unlock.coins_paid,
      creatorRevenue: unlock.creator_revenue,
      creator_revenue: unlock.creator_revenue,
      platformRevenue: unlock.platform_revenue,
      platform_revenue: unlock.platform_revenue,
      unlockedAt: unlock.inserted_at,
      unlocked_at: unlock.inserted_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
