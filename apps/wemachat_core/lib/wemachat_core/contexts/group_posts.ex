defmodule WemachatCore.Contexts.GroupPosts do
  @moduledoc """
  The GroupPosts context.
  Handles all business logic for posts and comments in public groups.
  """

  import Ecto.Query, warn: false
  alias WemachatDatabase.Repo
  alias WemachatDatabase.Schemas.{Group, GroupPost, GroupPostComment}
  alias WemachatCore.Contexts.Groups

  ## POSTS

  @doc """
  Create a post in a public group.
  Only owner and admins can create posts.
  Returns {:error, :not_public_group} if group is private.
  Returns {:error, :unauthorized} if user cannot post.
  """
  def create_post(attrs) do
    group_id = attrs[:group_id] || attrs["group_id"]
    author_id = attrs[:author_id] || attrs["author_id"]

    # Verify group is public
    group = Groups.get_group!(group_id)

    if group.group_type != "public" do
      {:error, :not_public_group}
    else
      # Verify user can post (owner or admin)
      if Groups.can_post?(group_id, author_id) do
        %GroupPost{}
        |> GroupPost.create_changeset(attrs)
        |> Repo.insert()
      else
        {:error, :unauthorized}
      end
    end
  end

  @doc """
  Get a single post by ID.
  """
  def get_post(id), do: Repo.get(GroupPost, id)

  @doc """
  Get a single post by ID, raises if not found.
  """
  def get_post!(id), do: Repo.get!(GroupPost, id)

  @doc """
  List posts for a group (paginated, newest first, pinned posts at top).
  """
  def list_group_posts(group_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    GroupPost
    |> where([p], p.group_id == ^group_id)
    |> order_by([p], desc: p.is_pinned, desc: p.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Update a post (text only).
  Only the author can update their own post.
  """
  def update_post(%GroupPost{} = post, author_id, attrs) do
    if post.author_id == author_id do
      post
      |> GroupPost.update_changeset(attrs)
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Delete a post.
  Only the author, group owner, or group admin can delete.
  """
  def delete_post(post_id, user_id) do
    post = get_post!(post_id)

    # Check if user is author, owner, or admin
    can_delete =
      post.author_id == user_id or
        Groups.owner?(post.group_id, user_id) or
        Groups.admin?(post.group_id, user_id)

    if can_delete do
      Repo.delete(post)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Like a post.
  Increments the likes counter.
  """
  def like_post(post_id) do
    post = get_post!(post_id)

    post
    |> GroupPost.stats_changeset(%{likes: post.likes + 1})
    |> Repo.update()
  end

  @doc """
  Pin/unpin a post.
  Only owner and admins can pin posts.
  """
  def pin_post(post_id, user_id, is_pinned) do
    post = get_post!(post_id)

    # Check if user is owner or admin
    can_pin = Groups.owner?(post.group_id, user_id) or Groups.admin?(post.group_id, user_id)

    if can_pin do
      post
      |> GroupPost.pin_changeset(is_pinned)
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  ## COMMENTS

  @doc """
  Create a comment on a post.
  All group members (including subscribers) can comment.
  """
  def create_comment(attrs) do
    post_id = attrs[:post_id] || attrs["post_id"]
    author_id = attrs[:author_id] || attrs["author_id"]

    post = get_post!(post_id)

    # Verify user is a member/subscriber of the group
    if Groups.member?(post.group_id, author_id) do
      Repo.transaction(fn ->
        # Create comment
        comment =
          %GroupPostComment{}
          |> GroupPostComment.create_changeset(attrs)
          |> Repo.insert!()

        # Update path if this is a reply (has parent)
        parent_id = attrs[:parent_id] || attrs["parent_id"]

        if parent_id do
          parent = get_comment!(parent_id)

          comment
          |> GroupPostComment.update_path_changeset(parent.path, parent.id)
          |> Repo.update!()
        else
          comment
        end
      end)
    else
      {:error, :not_a_member}
    end
  end

  @doc """
  Get a single comment by ID.
  """
  def get_comment(id), do: Repo.get(GroupPostComment, id)

  @doc """
  Get a single comment by ID, raises if not found.
  """
  def get_comment!(id), do: Repo.get!(GroupPostComment, id)

  @doc """
  List comments for a post with threading.
  Returns comments ordered by depth (top-level first) and creation time.
  """
  def list_post_comments(post_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)

    GroupPostComment
    |> where([c], c.post_id == ^post_id)
    |> order_by([c], asc: c.depth, asc: c.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  List top-level comments for a post (comments with no parent).
  """
  def list_top_level_comments(post_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    GroupPostComment
    |> where([c], c.post_id == ^post_id and is_nil(c.parent_id))
    |> order_by([c], desc: c.is_pinned, desc: c.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  List replies for a comment.
  """
  def list_comment_replies(comment_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    GroupPostComment
    |> where([c], c.parent_id == ^comment_id)
    |> order_by([c], asc: c.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Update a comment (text only).
  Only the author can update their own comment.
  """
  def update_comment(%GroupPostComment{} = comment, author_id, attrs) do
    if comment.author_id == author_id do
      comment
      |> GroupPostComment.update_changeset(attrs)
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Delete a comment.
  Only the author, post author, group owner, or group admin can delete.
  """
  def delete_comment(comment_id, user_id) do
    comment = get_comment!(comment_id)
    post = get_post!(comment.post_id)

    # Check if user is comment author, post author, owner, or admin
    can_delete =
      comment.author_id == user_id or
        post.author_id == user_id or
        Groups.owner?(post.group_id, user_id) or
        Groups.admin?(post.group_id, user_id)

    if can_delete do
      Repo.delete(comment)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Like a comment.
  Increments the likes counter.
  """
  def like_comment(comment_id) do
    comment = get_comment!(comment_id)

    comment
    |> GroupPostComment.stats_changeset(%{likes: comment.likes + 1})
    |> Repo.update()
  end

  @doc """
  Pin/unpin a comment.
  Only the post author, group owner, or group admin can pin comments.
  """
  def pin_comment(comment_id, user_id, is_pinned) do
    comment = get_comment!(comment_id)
    post = get_post!(comment.post_id)

    # Check if user is post author, owner, or admin
    can_pin =
      post.author_id == user_id or
        Groups.owner?(post.group_id, user_id) or
        Groups.admin?(post.group_id, user_id)

    if can_pin do
      comment
      |> GroupPostComment.pin_changeset(is_pinned)
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end
end
