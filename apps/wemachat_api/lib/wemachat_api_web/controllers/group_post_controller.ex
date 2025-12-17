defmodule WemachatApiWeb.GroupPostController do
  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.GroupPosts
  alias WemachatApiWeb.Plugs.FirebaseAuth

  plug FirebaseAuth

  @doc """
  Create a post in a public group.
  POST /api/v1/groups/:group_id/posts
  Body: {content_type, text?, media_url?, media_urls?, media_thumbnail_url?, media_type?}
  """
  def create(conn, %{"group_id" => group_id} = params) do
    user_id = conn.assigns[:current_user_id]

    attrs = %{
      group_id: group_id,
      author_id: user_id,
      content_type: params["content_type"] || "text",
      text: params["text"],
      media_url: params["media_url"],
      media_urls: params["media_urls"],
      media_thumbnail_url: params["media_thumbnail_url"],
      media_type: params["media_type"]
    }

    case GroupPosts.create_post(attrs) do
      {:ok, post} ->
        conn
        |> put_status(:created)
        |> json(post)

      {:error, :not_public_group} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Posts can only be created in public groups"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only group owner and admins can create posts"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create post", details: translate_errors(changeset)})
    end
  end

  @doc """
  Get a single post by ID.
  GET /api/v1/posts/:id
  """
  def show(conn, %{"id" => id}) do
    case GroupPosts.get_post(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Post not found"})

      post ->
        json(conn, post)
    end
  end

  @doc """
  List posts for a group.
  GET /api/v1/groups/:group_id/posts
  Query params: page, per_page
  """
  def index(conn, %{"group_id" => group_id} = params) do
    opts = [
      page: Map.get(params, "page", "1") |> String.to_integer(),
      per_page: Map.get(params, "perPage", "20") |> String.to_integer()
    ]

    posts = GroupPosts.list_group_posts(group_id, opts)
    json(conn, posts)
  end

  @doc """
  Update a post.
  PUT /api/v1/posts/:id
  Body: {text}
  """
  def update(conn, %{"id" => id} = params) do
    user_id = conn.assigns[:current_user_id]

    case GroupPosts.get_post(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Post not found"})

      post ->
        attrs = %{text: params["text"]}

        case GroupPosts.update_post(post, user_id, attrs) do
          {:ok, updated_post} ->
            json(conn, updated_post)

          {:error, :unauthorized} ->
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Only the post author can update the post"})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to update post", details: translate_errors(changeset)})
        end
    end
  end

  @doc """
  Delete a post.
  DELETE /api/v1/posts/:id
  """
  def delete(conn, %{"id" => id}) do
    user_id = conn.assigns[:current_user_id]

    case GroupPosts.delete_post(id, user_id) do
      {:ok, _post} ->
        conn
        |> put_status(:no_content)
        |> json(%{})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You don't have permission to delete this post"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to delete post"})
    end
  end

  @doc """
  Like a post.
  POST /api/v1/posts/:id/like
  """
  def like(conn, %{"id" => id}) do
    case GroupPosts.like_post(id) do
      {:ok, post} ->
        json(conn, post)

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to like post"})
    end
  end

  @doc """
  Pin/unpin a post.
  POST /api/v1/posts/:id/pin
  Body: {is_pinned: boolean}
  """
  def pin(conn, %{"id" => id, "is_pinned" => is_pinned}) do
    user_id = conn.assigns[:current_user_id]

    case GroupPosts.pin_post(id, user_id, is_pinned) do
      {:ok, post} ->
        json(conn, post)

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only group owner and admins can pin posts"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to pin post"})
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
