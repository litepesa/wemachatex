defmodule WemachatApiWeb.MarketplaceController do
  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.Marketplace
  alias WemachatApiWeb.Plugs.FirebaseAuth

  # Apply Firebase auth to protected routes
  plug FirebaseAuth
       when action not in [:index, :show, :comments]

  @doc """
  POST /api/v1/marketplace
  Create a marketplace item (auth required).
  """
  def create(conn, params) do
    user_id = conn.assigns.current_user_id
    transformed_params = transform_item_params(params, user_id)

    case Marketplace.create_item(transformed_params) do
      {:ok, item} ->
        conn
        |> put_status(:created)
        |> json(format_item(item))

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to create item", details: format_errors(changeset)})
    end
  end

  @doc """
  GET /api/v1/marketplace/:id
  Get a single marketplace item.
  Auto-increments view count.
  """
  def show(conn, %{"id" => id}) do
    case Marketplace.get_item(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Item not found"})

      item ->
        # Increment view count
        Marketplace.increment_views(item)

        conn
        |> put_status(:ok)
        |> json(format_item(item))
    end
  end

  @doc """
  GET /api/v1/marketplace
  Get marketplace feed (all items).
  """
  def index(conn, params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    items = Marketplace.get_feed(page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      items: Enum.map(items, &format_item/1),
      videos: Enum.map(items, &format_item/1),  # Flutter expects "videos" key
      page: page,
      per_page: per_page
    })
  end

  @doc """
  GET /api/v1/users/:user_id/marketplace
  Get marketplace items for a specific user.
  """
  def user_items(conn, %{"user_id" => user_id} = params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    items = Marketplace.list_user_items(user_id, page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      items: Enum.map(items, &format_item/1),
      videos: Enum.map(items, &format_item/1),  # Flutter expects "videos" key
      page: page,
      per_page: per_page
    })
  end

  @doc """
  GET /api/v1/users/:user_id/liked-marketplace
  Get marketplace items liked by a specific user.
  """
  def liked_items(conn, %{"user_id" => user_id} = params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    # Get liked item IDs
    liked_ids = Marketplace.get_liked_item_ids(user_id)

    # Fetch the actual items
    items = Marketplace.get_items_by_ids(liked_ids, page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      items: Enum.map(items, &format_item/1),
      videos: Enum.map(items, &format_item/1),  # Flutter expects "videos" key
      page: page,
      per_page: per_page
    })
  end

  @doc """
  PUT /api/v1/marketplace/:id
  Update a marketplace item (auth required, owner only).
  """
  def update(conn, %{"id" => id} = params) do
    user_id = conn.assigns.current_user_id

    with {:ok, item} <- get_item_by_id(id),
         :ok <- verify_owner(item, user_id),
         transformed_params <- transform_item_params(params, user_id),
         {:ok, updated_item} <- Marketplace.update_item(item, transformed_params) do
      conn
      |> put_status(:ok)
      |> json(format_item(updated_item))
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Item not found"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not authorized to update this item"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to update item", details: format_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/marketplace/:id
  Delete a marketplace item (auth required, owner only).
  """
  def delete(conn, %{"id" => id}) do
    user_id = conn.assigns.current_user_id

    with {:ok, item} <- get_item_by_id(id),
         :ok <- verify_owner(item, user_id),
         {:ok, _deleted} <- Marketplace.delete_item(item) do
      conn
      |> put_status(:ok)
      |> json(%{message: "Item deleted successfully"})
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Item not found"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not authorized to delete this item"})
    end
  end

  @doc """
  POST /api/v1/marketplace/:id/like
  Like an item (auth required).
  """
  def like(conn, %{"id" => id}) do
    user_id = conn.assigns.current_user_id

    case Marketplace.like_item(id, user_id) do
      {:ok, _like} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Item liked successfully"})

      {:error, :already_liked} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "You already liked this item"})

      {:error, _} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to like item"})
    end
  end

  @doc """
  DELETE /api/v1/marketplace/:id/like
  Unlike an item (auth required).
  """
  def unlike(conn, %{"id" => id}) do
    user_id = conn.assigns.current_user_id

    case Marketplace.unlike_item(id, user_id) do
      {:ok, _} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Item unliked successfully"})

      {:error, :not_liked} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "You haven't liked this item"})
    end
  end

  @doc """
  POST /api/v1/marketplace/:id/views
  Increment view count (auth required).
  """
  def increment_views(conn, %{"id" => id}) do
    case Marketplace.get_item(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Item not found"})

      item ->
        Marketplace.increment_views(item)

        conn
        |> put_status(:ok)
        |> json(%{message: "View count incremented"})
    end
  end

  @doc """
  GET /api/v1/marketplace/:id/comments
  Get comments for an item.
  """
  def comments(conn, %{"id" => id} = params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    comments = Marketplace.get_item_comments(id, page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      comments: comments,
      page: page,
      per_page: per_page
    })
  end

  @doc """
  POST /api/v1/marketplace/:id/comments
  Create a comment on an item (auth required).
  """
  def create_comment(conn, %{"id" => id} = params) do
    user_id = conn.assigns.current_user_id

    comment_params = %{
      item_id: id,
      user_id: user_id,
      user_name: params["user_name"] || params["userName"],
      user_image: params["user_image"] || params["userImage"],
      comment_text: params["content"] || params["comment_text"] || params["commentText"],
      media_url: params["media_url"] || params["mediaUrl"],
      image_urls: params["image_urls"] || params["imageUrls"] || [],
      replied_to_comment_id: params["replied_to_comment_id"] || params["repliedToCommentId"],
      parent_comment_id: params["parent_comment_id"] || params["parentCommentId"],
      replied_to_author_name: params["replied_to_author_name"] || params["repliedToAuthorName"]
    }

    case Marketplace.create_comment(comment_params) do
      {:ok, comment} ->
        conn
        |> put_status(:created)
        |> json(comment)

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to create comment", details: format_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/marketplace/comments/:id
  Delete a comment (auth required, author only).
  """
  def delete_comment(conn, %{"id" => comment_id}) do
    case Marketplace.delete_comment(comment_id) do
      {:ok, _} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Comment deleted successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Comment not found"})
    end
  end

  @doc """
  POST /api/v1/marketplace/comments/:id/pin
  Pin a comment (auth required, item owner only).
  """
  def pin_comment(conn, %{"id" => comment_id}) do
    case Marketplace.pin_comment(comment_id) do
      {:ok, comment} ->
        conn
        |> put_status(:ok)
        |> json(comment)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Comment not found"})
    end
  end

  @doc """
  DELETE /api/v1/marketplace/comments/:id/pin
  Unpin a comment (auth required, item owner only).
  """
  def unpin_comment(conn, %{"id" => comment_id}) do
    case Marketplace.unpin_comment(comment_id) do
      {:ok, comment} ->
        conn
        |> put_status(:ok)
        |> json(comment)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Comment not found"})
    end
  end

  @doc """
  POST /api/v1/marketplace/:id/boost
  Boost a marketplace item (auth required).
  """
  def boost(conn, %{"id" => id} = params) do
    user_id = conn.assigns.current_user_id

    with {:ok, item} <- get_item_by_id(id),
         :ok <- verify_owner(item, user_id),
         {:ok, boosted_item} <- Marketplace.boost_item(item, params) do
      conn
      |> put_status(:ok)
      |> json(format_item(boosted_item))
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Item not found"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not authorized to boost this item"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to boost item", reason: inspect(reason)})
    end
  end

  # Private Helper Functions

  defp get_item_by_id(id) do
    case Marketplace.get_item(id) do
      nil -> {:error, :not_found}
      item -> {:ok, item}
    end
  end

  defp verify_owner(%{user_id: item_user_id}, user_id) do
    if item_user_id == user_id do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp transform_item_params(params, user_id) do
    %{
      user_id: user_id,
      user_name: params["user_name"] || params["userName"],
      user_image: params["user_image"] || params["userImage"],
      video_url: params["video_url"] || params["videoUrl"],
      thumbnail_url: params["thumbnail_url"] || params["thumbnailUrl"],
      caption: params["caption"],
      tags: params["tags"],
      price: parse_price(params["price"]),
      is_multiple_images: params["is_multiple_images"] || params["isMultipleImages"] || false,
      image_urls: params["image_urls"] || params["imageUrls"] || [],
      is_boosted: params["is_boosted"] || params["isBoosted"] || false,
      boost_tier: params["boost_tier"] || params["boostTier"] || "none",
      super_boost: params["super_boost"] || params["superBoost"] || false
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  defp format_item(item) do
    %{
      id: item.id,
      userId: item.user_id,
      userName: item.user_name,
      userImage: item.user_image,
      videoUrl: item.video_url,
      thumbnailUrl: item.thumbnail_url,
      caption: item.caption,
      price: to_string(item.price),
      tags: item.tags,
      views: item.views,
      viewsCount: item.views,  # Flutter expects both formats
      likes: item.likes,
      likesCount: item.likes,
      comments: item.comments,
      commentsCount: item.comments,
      shares: item.shares,
      sharesCount: item.shares,
      isActive: item.is_active,
      isFeatured: item.is_featured,
      isVerified: item.is_verified,
      isMultipleImages: item.is_multiple_images,
      imageUrls: item.image_urls,
      isBoosted: item.is_boosted,
      boostTier: item.boost_tier,
      superBoost: item.super_boost,
      createdAt: item.inserted_at,
      updatedAt: item.updated_at
    }
  end

  defp parse_int(nil, default), do: default
  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end
  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(_, default), do: default

  defp parse_price(nil), do: Decimal.new("0.0")
  defp parse_price(value) when is_number(value), do: Decimal.new(to_string(value))
  defp parse_price(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      :error -> Decimal.new("0.0")
    end
  end
  defp parse_price(_), do: Decimal.new("0.0")

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
