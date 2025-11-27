defmodule WemachatCore.Contexts.Marketplace do
  @moduledoc """
  The Marketplace context.
  Handles all business logic for marketplace items (clone of videos but without expiry).

  Marketplace items are user-based listings with pricing.
  Unlike videos (72-hour expiry), marketplace items persist until manually deactivated.
  """

  import Ecto.Query, warn: false
  alias WemachatDatabase.Repo
  alias WemachatDatabase.Schemas.{MarketplaceItem, MarketplaceLike, MarketplaceComment}

  ## CREATE

  @doc """
  Creates a marketplace item.
  No expiry is set (unlike videos).
  """
  def create_item(attrs \\ %{}) do
    %MarketplaceItem{}
    |> MarketplaceItem.create_changeset(attrs)
    |> Repo.insert()
  end

  ## READ

  @doc """
  Gets a single marketplace item by ID.
  Returns nil if item doesn't exist or is not active.
  """
  def get_item(id) do
    MarketplaceItem
    |> where([i], i.id == ^id and i.is_active == true)
    |> Repo.one()
  end

  @doc """
  Gets a single marketplace item by ID, raises if not found.
  """
  def get_item!(id) do
    MarketplaceItem
    |> where([i], i.id == ^id and i.is_active == true)
    |> Repo.one!()
  end

  @doc """
  Lists items from a user (only active items).
  """
  def list_user_items(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    MarketplaceItem
    |> where([i], i.user_id == ^user_id)
    |> where([i], i.is_active == true)
    |> order_by([i], desc: i.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Gets marketplace feed (all items).
  Ordered by newest first.
  """
  def get_feed(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    MarketplaceItem
    |> where([i], i.is_active == true)
    |> order_by([i], desc: i.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Gets discover feed (trending items).
  Ordered by engagement (views + likes).
  """
  def get_discover_feed(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    MarketplaceItem
    |> where([i], i.is_active == true)
    |> order_by([i], desc: i.views + i.likes)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Gets items by list of IDs.
  Used for fetching liked items.
  """
  def get_items_by_ids(ids, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    MarketplaceItem
    |> where([i], i.id in ^ids and i.is_active == true)
    |> order_by([i], desc: i.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Search items by caption.
  Uses trigram similarity for fuzzy search.
  """
  def search_items(query, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    search_query = "%#{query}%"

    MarketplaceItem
    |> where([i], i.is_active == true)
    |> where([i], ilike(i.caption, ^search_query))
    |> order_by([i], desc: i.views)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  ## UPDATE

  @doc """
  Updates a marketplace item.
  """
  def update_item(%MarketplaceItem{} = item, attrs) do
    item
    |> MarketplaceItem.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Increment view count.
  """
  def increment_views(%MarketplaceItem{} = item) do
    item
    |> Ecto.Changeset.change(views: item.views + 1)
    |> Repo.update()
  end

  @doc """
  Increment share count.
  """
  def increment_shares(%MarketplaceItem{} = item) do
    item
    |> Ecto.Changeset.change(shares: item.shares + 1)
    |> Repo.update()
  end

  @doc """
  Deactivate an item (soft delete).
  """
  def deactivate_item(%MarketplaceItem{} = item) do
    item
    |> Ecto.Changeset.change(is_active: false)
    |> Repo.update()
  end

  ## DELETE

  @doc """
  Deletes a marketplace item (hard delete).
  """
  def delete_item(%MarketplaceItem{} = item) do
    Repo.delete(item)
  end

  ## LIKES

  @doc """
  Likes an item.
  Returns {:error, :already_liked} if already liked.
  Auto-increments item likes count via database trigger.
  """
  def like_item(item_id, user_id) do
    %MarketplaceLike{}
    |> MarketplaceLike.changeset(%{item_id: item_id, user_id: user_id})
    |> Repo.insert()
    |> case do
      {:ok, like} -> {:ok, like}
      {:error, %{errors: [item_id_user_id: _]}} -> {:error, :already_liked}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Unlikes an item.
  Auto-decrements item likes count via database trigger.
  """
  def unlike_item(item_id, user_id) do
    case Repo.get_by(MarketplaceLike, item_id: item_id, user_id: user_id) do
      nil -> {:error, :not_liked}
      like -> Repo.delete(like)
    end
  end

  @doc """
  Checks if user liked an item.
  """
  def liked?(item_id, user_id) do
    Repo.exists?(from l in MarketplaceLike, where: l.item_id == ^item_id and l.user_id == ^user_id)
  end

  @doc """
  Gets list of liked item IDs for a user.
  """
  def get_liked_item_ids(user_id) do
    MarketplaceLike
    |> where([l], l.user_id == ^user_id)
    |> select([l], l.item_id)
    |> Repo.all()
  end

  ## COMMENTS

  @doc """
  Creates a comment on an item.
  Auto-increments item comments count via database trigger.
  """
  def create_comment(attrs \\ %{}) do
    %MarketplaceComment{}
    |> MarketplaceComment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets comments for an item.
  """
  def get_item_comments(item_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    MarketplaceComment
    |> where([c], c.item_id == ^item_id)
    |> where([c], c.is_active == true)
    |> order_by([c], desc: c.is_pinned, desc: c.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Deletes a comment.
  Auto-decrements item comments count via database trigger.
  """
  def delete_comment(comment_id) do
    case Repo.get(MarketplaceComment, comment_id) do
      nil -> {:error, :not_found}
      comment -> Repo.delete(comment)
    end
  end

  @doc """
  Pins a comment (owner/admin only).
  """
  def pin_comment(comment_id) do
    case Repo.get(MarketplaceComment, comment_id) do
      nil -> {:error, :not_found}
      comment ->
        comment
        |> Ecto.Changeset.change(is_pinned: true)
        |> Repo.update()
    end
  end

  @doc """
  Unpins a comment.
  """
  def unpin_comment(comment_id) do
    case Repo.get(MarketplaceComment, comment_id) do
      nil -> {:error, :not_found}
      comment ->
        comment
        |> Ecto.Changeset.change(is_pinned: false)
        |> Repo.update()
    end
  end

  ## ADMIN / MODERATION

  @doc """
  Admin changeset for moderation (boost score, geo-targeting, etc.)
  """
  def admin_update(%MarketplaceItem{} = item, attrs) do
    item
    |> MarketplaceItem.admin_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Pin an item (always shown first in feed).
  """
  def pin_item(%MarketplaceItem{} = item) do
    item
    |> Ecto.Changeset.change(is_pinned: true)
    |> Repo.update()
  end

  @doc """
  Unpin an item.
  """
  def unpin_item(%MarketplaceItem{} = item) do
    item
    |> Ecto.Changeset.change(is_pinned: false)
    |> Repo.update()
  end

  @doc """
  Set item visibility (public, limited, hidden).
  """
  def set_visibility(%MarketplaceItem{} = item, level) when level in ["public", "limited", "hidden"] do
    item
    |> Ecto.Changeset.change(visibility_level: level)
    |> Repo.update()
  end

  @doc """
  Boost a marketplace item (deduct coins, set boost tier).
  """
  def boost_item(%MarketplaceItem{} = item, attrs) do
    item
    |> Ecto.Changeset.change(%{
      is_boosted: true,
      boost_tier: attrs[:boost_tier] || attrs["boost_tier"],
      super_boost: attrs[:super_boost] || attrs["super_boost"] || false
    })
    |> Repo.update()
  end
end
