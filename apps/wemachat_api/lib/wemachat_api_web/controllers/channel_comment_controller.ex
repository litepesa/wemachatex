defmodule WemachatApiWeb.ChannelCommentController do
  @moduledoc """
  Controller for channel post comments (multi-threaded with unlimited nesting).
  """
  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.Channels
  alias WemachatApiWeb.Plugs.FirebaseAuth

  plug FirebaseAuth

  ## COMMENT CRUD

  @doc """
  GET /api/v1/posts/:post_id/comments
  List top-level comments for a post.
  """
  def index(conn, %{"post_id" => post_id} = params) do
    opts = [
      page: String.to_integer(params["page"] || "1"),
      per_page: String.to_integer(params["per_page"] || "20")
    ]

    comments = Channels.list_post_comments(post_id, opts)

    conn
    |> put_status(:ok)
    |> json(%{comments: Enum.map(comments, &format_comment/1)})
  end

  @doc """
  GET /api/v1/comments/:comment_id/replies
  List replies to a comment.
  """
  def list_replies(conn, %{"comment_id" => comment_id} = params) do
    opts = [
      page: String.to_integer(params["page"] || "1"),
      per_page: String.to_integer(params["per_page"] || "20")
    ]

    replies = Channels.list_comment_replies(comment_id, opts)

    conn
    |> put_status(:ok)
    |> json(%{replies: Enum.map(replies, &format_comment/1)})
  end

  @doc """
  GET /api/v1/comments/:id
  Get a single comment by ID.
  """
  def show(conn, %{"id" => id}) do
    case Channels.get_comment(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Comment not found"})

      comment ->
        conn
        |> put_status(:ok)
        |> json(%{comment: format_comment(comment)})
    end
  end

  @doc """
  POST /api/v1/comments
  Create a new comment or reply.
  Body: {postId, text, parentId?, mediaUrl?, mediaType?}
  """
  def create(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)

    attrs = %{
      "post_id" => params["postId"] || params["post_id"],
      "author_id" => user_id,
      "parent_id" => params["parentId"] || params["parent_id"],
      "text" => params["text"],
      "media_url" => params["mediaUrl"] || params["media_url"],
      "media_type" => params["mediaType"] || params["media_type"]
    }

    case Channels.create_comment(attrs) do
      {:ok, comment} ->
        conn
        |> put_status(:created)
        |> json(%{comment: format_comment(comment)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create comment", errors: format_errors(changeset)})
    end
  end

  @doc """
  PUT /api/v1/comments/:id
  Update a comment (text only, author only).
  Body: {text}
  """
  def update(conn, %{"id" => id} = params) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Channels.get_comment(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Comment not found"})

      comment ->
        if comment.author_id == user_id do
          case Channels.update_comment(comment, %{"text" => params["text"]}) do
            {:ok, updated_comment} ->
              conn
              |> put_status(:ok)
              |> json(%{comment: format_comment(updated_comment)})

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Failed to update comment", errors: format_errors(changeset)})
          end
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "You can only update your own comments"})
        end
    end
  end

  @doc """
  DELETE /api/v1/comments/:id
  Delete a comment (author, post author, or channel owner/admin/moderator).
  """
  def delete(conn, %{"id" => id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Channels.get_comment(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Comment not found"})

      comment ->
        # Get the post to check permissions
        post = Channels.get_post(comment.post_id)

        can_delete =
          comment.author_id == user_id or
            post.author_id == user_id or
            Channels.is_channel_owner?(post.channel_id, user_id) or
            Channels.is_channel_member?(post.channel_id, user_id)

        if can_delete do
          case Channels.delete_comment(comment) do
            {:ok, _} ->
              conn
              |> put_status(:ok)
              |> json(%{message: "Comment deleted successfully"})

            {:error, _} ->
              conn
              |> put_status(:internal_server_error)
              |> json(%{error: "Failed to delete comment"})
          end
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "You don't have permission to delete this comment"})
        end
    end
  end

  ## COMMENT INTERACTIONS

  @doc """
  POST /api/v1/comments/:id/like
  Like a comment.
  """
  def like(conn, %{"id" => id}) do
    case Channels.like_comment(id) do
      {:ok, comment} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Comment liked",
          likes: comment.likes
        })

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to like comment"})
    end
  end

  @doc """
  DELETE /api/v1/comments/:id/like
  Unlike a comment.
  """
  def unlike(conn, %{"id" => id}) do
    case Channels.unlike_comment(id) do
      {:ok, comment} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Comment unliked",
          likes: comment.likes
        })

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to unlike comment"})
    end
  end

  ## COMMENT MODERATION

  @doc """
  POST /api/v1/comments/:id/pin
  Pin a comment (post author or channel owner/admin/moderator only).
  """
  def pin(conn, %{"id" => id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Channels.get_comment(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Comment not found"})

      comment ->
        # Get the post to check permissions
        post = Channels.get_post(comment.post_id)

        can_pin =
          post.author_id == user_id or
            Channels.is_channel_owner?(post.channel_id, user_id) or
            Channels.is_channel_member?(post.channel_id, user_id)

        if can_pin do
          case Channels.pin_comment(id) do
            {:ok, pinned_comment} ->
              conn
              |> put_status(:ok)
              |> json(%{
                message: "Comment pinned",
                comment: format_comment(pinned_comment)
              })

            {:error, _} ->
              conn
              |> put_status(:internal_server_error)
              |> json(%{error: "Failed to pin comment"})
          end
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "You don't have permission to pin comments"})
        end
    end
  end

  @doc """
  DELETE /api/v1/comments/:id/pin
  Unpin a comment (post author or channel owner/admin/moderator only).
  """
  def unpin(conn, %{"id" => id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Channels.get_comment(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Comment not found"})

      comment ->
        # Get the post to check permissions
        post = Channels.get_post(comment.post_id)

        can_unpin =
          post.author_id == user_id or
            Channels.is_channel_owner?(post.channel_id, user_id) or
            Channels.is_channel_member?(post.channel_id, user_id)

        if can_unpin do
          case Channels.unpin_comment(id) do
            {:ok, unpinned_comment} ->
              conn
              |> put_status(:ok)
              |> json(%{
                message: "Comment unpinned",
                comment: format_comment(unpinned_comment)
              })

            {:error, _} ->
              conn
              |> put_status(:internal_server_error)
              |> json(%{error: "Failed to unpin comment"})
          end
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "You don't have permission to unpin comments"})
        end
    end
  end

  ## PRIVATE HELPERS

  defp format_comment(comment) do
    %{
      id: comment.id,
      postId: comment.post_id,
      post_id: comment.post_id,
      authorId: comment.author_id,
      author_id: comment.author_id,
      parentId: comment.parent_id,
      parent_id: comment.parent_id,
      path: comment.path,
      depth: comment.depth,
      text: comment.text,
      mediaUrl: comment.media_url,
      media_url: comment.media_url,
      mediaType: comment.media_type,
      media_type: comment.media_type,
      likes: comment.likes,
      repliesCount: comment.replies_count,
      replies_count: comment.replies_count,
      isPinned: comment.is_pinned,
      is_pinned: comment.is_pinned,
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
end
