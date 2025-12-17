defmodule WemachatApiWeb.GroupPostCommentController do
  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.GroupPosts
  alias WemachatApiWeb.Plugs.FirebaseAuth

  plug FirebaseAuth

  @doc """
  Create a comment on a post.
  POST /api/v1/posts/:post_id/comments
  Body: {text, parent_id?, media_url?, media_type?}
  """
  def create(conn, %{"post_id" => post_id} = params) do
    user_id = conn.assigns[:current_user_id]

    attrs = %{
      post_id: post_id,
      author_id: user_id,
      parent_id: params["parent_id"],
      text: params["text"],
      media_url: params["media_url"],
      media_type: params["media_type"]
    }

    case GroupPosts.create_comment(attrs) do
      {:ok, comment} ->
        conn
        |> put_status(:created)
        |> json(comment)

      {:error, :not_a_member} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only group members can comment"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create comment", details: translate_errors(changeset)})
    end
  end

  @doc """
  Get a single comment by ID.
  GET /api/v1/comments/:id
  """
  def show(conn, %{"id" => id}) do
    case GroupPosts.get_comment(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Comment not found"})

      comment ->
        json(conn, comment)
    end
  end

  @doc """
  List comments for a post.
  GET /api/v1/posts/:post_id/comments
  Query params: page, per_page, top_level_only
  """
  def index(conn, %{"post_id" => post_id} = params) do
    opts = [
      page: Map.get(params, "page", "1") |> String.to_integer(),
      per_page: Map.get(params, "perPage", "50") |> String.to_integer()
    ]

    # Check if we should only fetch top-level comments
    comments =
      if params["top_level_only"] == "true" do
        GroupPosts.list_top_level_comments(post_id, opts)
      else
        GroupPosts.list_post_comments(post_id, opts)
      end

    json(conn, comments)
  end

  @doc """
  List replies for a comment.
  GET /api/v1/comments/:comment_id/replies
  Query params: page, per_page
  """
  def list_replies(conn, %{"comment_id" => comment_id} = params) do
    opts = [
      page: Map.get(params, "page", "1") |> String.to_integer(),
      per_page: Map.get(params, "perPage", "20") |> String.to_integer()
    ]

    replies = GroupPosts.list_comment_replies(comment_id, opts)
    json(conn, replies)
  end

  @doc """
  Update a comment.
  PUT /api/v1/comments/:id
  Body: {text}
  """
  def update(conn, %{"id" => id} = params) do
    user_id = conn.assigns[:current_user_id]

    case GroupPosts.get_comment(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Comment not found"})

      comment ->
        attrs = %{text: params["text"]}

        case GroupPosts.update_comment(comment, user_id, attrs) do
          {:ok, updated_comment} ->
            json(conn, updated_comment)

          {:error, :unauthorized} ->
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Only the comment author can update the comment"})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to update comment", details: translate_errors(changeset)})
        end
    end
  end

  @doc """
  Delete a comment.
  DELETE /api/v1/comments/:id
  """
  def delete(conn, %{"id" => id}) do
    user_id = conn.assigns[:current_user_id]

    case GroupPosts.delete_comment(id, user_id) do
      {:ok, _comment} ->
        conn
        |> put_status(:no_content)
        |> json(%{})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You don't have permission to delete this comment"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to delete comment"})
    end
  end

  @doc """
  Like a comment.
  POST /api/v1/comments/:id/like
  """
  def like(conn, %{"id" => id}) do
    case GroupPosts.like_comment(id) do
      {:ok, comment} ->
        json(conn, comment)

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to like comment"})
    end
  end

  @doc """
  Pin/unpin a comment.
  POST /api/v1/comments/:id/pin
  Body: {is_pinned: boolean}
  """
  def pin(conn, %{"id" => id, "is_pinned" => is_pinned}) do
    user_id = conn.assigns[:current_user_id]

    case GroupPosts.pin_comment(id, user_id, is_pinned) do
      {:ok, comment} ->
        json(conn, comment)

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only post author, group owner, or admins can pin comments"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to pin comment"})
    end
  end

  # Helper function to translate changeset errors
  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
