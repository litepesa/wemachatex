defmodule WemachatCore.Contexts.Videos do
  @moduledoc """
  The Videos context.
  Handles all business logic for videos.

  NOTE: Videos are now user-based (not channel-based).
  Each video belongs directly to a user via user_id.
  Videos no longer expire and stay on the platform permanently.
  """

  import Ecto.Query, warn: false
  alias WemachatDatabase.Repo
  alias WemachatDatabase.Schemas.{Video, VideoLike, VideoComment, User}
  alias WemachatCore.Contexts.Users

  ## CREATE

  @doc """
  Creates a video.
  Videos no longer expire and stay on the platform permanently.
  Increments user's videos_count.
  """
  def create_video(attrs \\ %{}) do
    with {:ok, video} <-
           %Video{}
           |> Video.create_changeset(attrs)
           |> Repo.insert(),
         user when not is_nil(user) <- Users.get_user(video.user_id),
         {:ok, _} <- Users.increment_videos(user) do
      {:ok, video}
    else
      {:error, changeset} -> {:error, changeset}
      nil -> {:error, :user_not_found}
    end
  end

  ## READ

  @doc """
  Gets a single video by ID.
  Returns nil if video doesn't exist.
  Note: Videos now stay on platform forever (no expiry).
  """
  def get_video(id) do
    Video
    |> where([v], v.id == ^id and v.is_active == true)
    |> Repo.one()
  end

  @doc """
  Gets a single video by ID, raises if not found.
  Note: Videos now stay on platform forever (no expiry).
  """
  def get_video!(id) do
    Video
    |> where([v], v.id == ^id and v.is_active == true)
    |> Repo.one!()
  end

  @doc """
  Lists videos from a user (only active videos).
  Note: Videos now stay on platform forever (no expiry).
  """
  def list_user_videos(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    Video
    |> where([v], v.user_id == ^user_id)
    |> where([v], v.is_active == true)
    |> order_by([v], desc: v.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Gets feed of videos (TikTok-style).
  Ordered by newest first.
  Note: Videos now stay on platform forever (no expiry).
  """
  def get_feed(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    Video
    |> where([v], v.is_active == true)
    |> order_by([v], desc: v.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Gets discover feed (trending videos).
  Ordered by engagement (views + likes).
  Note: Videos now stay on platform forever (no expiry).
  """
  def get_discover_feed(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    Video
    |> where([v], v.is_active == true)
    |> order_by([v], desc: v.views + v.likes)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Search videos by caption.
  Note: Videos now stay on platform forever (no expiry).
  """
  def search_videos(query, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    search_query = "%#{query}%"

    Video
    |> where([v], v.is_active == true)
    |> where([v], ilike(v.caption, ^search_query))
    |> order_by([v], desc: v.views)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  ## UPDATE

  @doc """
  Updates a video.
  """
  def update_video(%Video{} = video, attrs) do
    video
    |> Video.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Increment view count.
  """
  def increment_views(%Video{} = video) do
    video
    |> Ecto.Changeset.change(views: video.views + 1)
    |> Repo.update()
  end

  @doc """
  Increment share count.
  """
  def increment_shares(%Video{} = video) do
    video
    |> Ecto.Changeset.change(shares: video.shares + 1)
    |> Repo.update()
  end

  ## DELETE

  @doc """
  Soft deletes a video (sets is_active to false).
  Decrements user's videos_count.
  """
  def deactivate_video(%Video{} = video) do
    with {:ok, video} <-
           video
           |> Ecto.Changeset.change(is_active: false)
           |> Repo.update(),
         user when not is_nil(user) <- Users.get_user(video.user_id),
         {:ok, _} <- Users.decrement_videos(user) do
      {:ok, video}
    end
  end

  @doc """
  Hard deletes a video.
  Decrements user's videos_count.
  """
  def delete_video(%Video{} = video) do
    with {:ok, video} <- Repo.delete(video),
         user when not is_nil(user) <- Users.get_user(video.user_id),
         {:ok, _} <- Users.decrement_videos(user) do
      {:ok, video}
    end
  end

  ## LIKES

  @doc """
  Like a video.
  """
  def like_video(user_id, video_id) do
    attrs = %{user_id: user_id, video_id: video_id}

    with {:ok, _like} <-
           %VideoLike{}
           |> VideoLike.changeset(attrs)
           |> Repo.insert(),
         video when not is_nil(video) <- get_video(video_id),
         {:ok, updated} <-
           video
           |> Ecto.Changeset.change(likes: video.likes + 1)
           |> Repo.update() do
      {:ok, updated}
    else
      {:error, changeset} -> {:error, changeset}
      nil -> {:error, :video_not_found_or_expired}
    end
  end

  @doc """
  Unlike a video.
  """
  def unlike_video(user_id, video_id) do
    like = Repo.get_by(VideoLike, user_id: user_id, video_id: video_id)

    case like do
      nil ->
        {:ok, :not_liked}

      like ->
        with {:ok, _} <- Repo.delete(like),
             video when not is_nil(video) <- get_video(video_id),
             {:ok, updated} <-
               video
               |> Ecto.Changeset.change(likes: max(0, video.likes - 1))
               |> Repo.update() do
          {:ok, updated}
        else
          {:error, changeset} -> {:error, changeset}
          nil -> {:error, :video_not_found_or_expired}
        end
    end
  end

  @doc """
  Check if user liked a video.
  """
  def liked?(user_id, video_id) do
    query =
      from l in VideoLike,
        where: l.user_id == ^user_id and l.video_id == ^video_id

    Repo.exists?(query)
  end

  ## COMMENTS

  @doc """
  Create a comment on a video.
  """
  def create_comment(attrs \\ %{}) do
    with {:ok, comment} <-
           %VideoComment{}
           |> VideoComment.create_changeset(attrs)
           |> Repo.insert(),
         video when not is_nil(video) <- get_video(comment.video_id),
         {:ok, _} <-
           video
           |> Ecto.Changeset.change(comments: video.comments + 1)
           |> Repo.update() do
      {:ok, comment}
    else
      {:error, changeset} -> {:error, changeset}
      nil -> {:error, :video_not_found_or_expired}
    end
  end

  @doc """
  Update a comment.
  """
  def update_comment(%VideoComment{} = comment, attrs) do
    comment
    |> VideoComment.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a comment.
  """
  def delete_comment(%VideoComment{} = comment) do
    with {:ok, comment} <- Repo.delete(comment),
         video when not is_nil(video) <- get_video(comment.video_id),
         {:ok, _} <-
           video
           |> Ecto.Changeset.change(comments: max(0, video.comments - 1))
           |> Repo.update() do
      {:ok, comment}
    end
  end

  @doc """
  Get comments for a video (paginated).
  """
  def get_video_comments(video_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    VideoComment
    |> where([c], c.video_id == ^video_id)
    |> order_by([c], desc: c.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  ## STATISTICS

  @doc """
  Count active videos.
  """
  def count_active_videos do
    Video
    |> where([v], v.is_active == true)
    |> Repo.aggregate(:count)
  end
end
