defmodule WemachatCore.Contexts.Moments do
  @moduledoc """
  The Moments context.
  Handles all business logic for posts (status updates), likes, and comments.
  Similar to Facebook feed or WeChat Moments.
  """

  import Ecto.Query, warn: false
  alias WemachatDatabase.Repo
  alias WemachatDatabase.Schemas.{Post, PostLike, PostComment}
  alias WemachatCore.Contexts.Users

  ## POSTS

  @doc """
  Create a post.
  """
  def create_post(attrs \\ %{}) do
    %Post{}
    |> Post.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Get a single post by ID (only if active).
  """
  def get_post(id) do
    Post
    |> where([p], p.id == ^id and p.is_active == true)
    |> Repo.one()
  end

  @doc """
  Get a single post by ID, raises if not found.
  """
  def get_post!(id) do
    Post
    |> where([p], p.id == ^id and p.is_active == true)
    |> Repo.one!()
  end

  @doc """
  List posts from a specific user.
  """
  def list_user_posts(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    Post
    |> where([p], p.user_id == ^user_id and p.is_active == true)
    |> order_by([p], desc: p.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Get feed for a user (posts from users they follow + their own posts).
  Ordered by newest first.
  """
  def get_feed(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    # Get list of users the current user follows
    followed_user_ids = Users.get_following_ids(user_id)

    # Include the user's own posts
    all_user_ids = [user_id | followed_user_ids]

    Post
    |> where([p], p.user_id in ^all_user_ids and p.is_active == true)
    |> where([p], p.visibility in ["public", "friends"])
    |> order_by([p], desc: p.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Get discover feed (all public posts, trending).
  Ordered by engagement (likes + comments).
  """
  def get_discover_feed(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    Post
    |> where([p], p.visibility == "public" and p.is_active == true)
    |> order_by([p], desc: p.likes_count + p.comments_count, desc: p.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Search posts by content text.
  """
  def search_posts(query, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    search_query = "%#{query}%"

    Post
    |> where([p], p.visibility == "public" and p.is_active == true)
    |> where([p], ilike(p.content_text, ^search_query))
    |> order_by([p], desc: p.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Update a post.
  """
  def update_post(%Post{} = post, attrs) do
    post
    |> Post.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft delete a post.
  """
  def delete_post(%Post{} = post) do
    post
    |> Post.update_changeset(%{is_active: false})
    |> Repo.update()
  end

  ## LIKES

  @doc """
  Like a post.
  """
  def like_post(user_id, post_id) do
    attrs = %{user_id: user_id, post_id: post_id}

    Repo.transaction(fn ->
      # Create like
      like =
        %PostLike{}
        |> PostLike.changeset(attrs)
        |> Repo.insert!()

      # Increment post likes count
      post = get_post!(post_id)

      post
      |> Ecto.Changeset.change(likes_count: post.likes_count + 1)
      |> Repo.update!()

      like
    end)
    |> case do
      {:ok, like} -> {:ok, like}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Unlike a post.
  """
  def unlike_post(user_id, post_id) do
    like = Repo.get_by(PostLike, user_id: user_id, post_id: post_id)

    case like do
      nil ->
        {:ok, :not_liked}

      like ->
        Repo.transaction(fn ->
          # Delete like
          Repo.delete!(like)

          # Decrement post likes count
          post = get_post!(post_id)

          post
          |> Ecto.Changeset.change(likes_count: max(0, post.likes_count - 1))
          |> Repo.update!()
        end)
        |> case do
          {:ok, _} -> {:ok, :unliked}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Check if user liked a post.
  """
  def liked?(user_id, post_id) do
    query =
      from l in PostLike,
        where: l.user_id == ^user_id and l.post_id == ^post_id

    Repo.exists?(query)
  end

  ## COMMENTS

  @doc """
  Create a comment on a post.
  """
  def create_comment(attrs \\ %{}) do
    Repo.transaction(fn ->
      # Create comment
      comment =
        %PostComment{}
        |> PostComment.create_changeset(attrs)
        |> Repo.insert!()

      # Increment post comments count
      post = get_post!(comment.post_id)

      post
      |> Ecto.Changeset.change(comments_count: post.comments_count + 1)
      |> Repo.update!()

      comment
    end)
    |> case do
      {:ok, comment} -> {:ok, comment}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get a single comment by ID.
  """
  def get_comment(id) do
    PostComment
    |> where([c], c.id == ^id and c.is_deleted == false)
    |> Repo.one()
  end

  @doc """
  Get comments for a post (paginated).
  """
  def list_post_comments(post_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    PostComment
    |> where([c], c.post_id == ^post_id and c.is_deleted == false)
    |> order_by([c], asc: c.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Update a comment.
  """
  def update_comment(%PostComment{} = comment, attrs) do
    comment
    |> PostComment.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft delete a comment.
  """
  def delete_comment(%PostComment{} = comment) do
    Repo.transaction(fn ->
      # Soft delete comment
      updated =
        comment
        |> PostComment.delete_changeset()
        |> Repo.update!()

      # Decrement post comments count
      post = get_post!(comment.post_id)

      post
      |> Ecto.Changeset.change(comments_count: max(0, post.comments_count - 1))
      |> Repo.update!()

      updated
    end)
    |> case do
      {:ok, comment} -> {:ok, comment}
      {:error, reason} -> {:error, reason}
    end
  end

  ## STATISTICS

  @doc """
  Count active posts.
  """
  def count_posts do
    Post
    |> where([p], p.is_active == true)
    |> Repo.aggregate(:count)
  end

  @doc """
  Count user's posts.
  """
  def count_user_posts(user_id) do
    Post
    |> where([p], p.user_id == ^user_id and p.is_active == true)
    |> Repo.aggregate(:count)
  end
end
