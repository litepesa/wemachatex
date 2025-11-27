defmodule WemachatCore.Contexts.Recommendations do
  @moduledoc """
  The Recommendations context.
  Handles the "For You" feed recommendation system with admin controls and pattern matching.

  Key Features:
  - Exclusion-based filtering (easier than prediction)
  - Admin boost controls
  - Silent push system (no user notifications)
  - Geo-targeting
  - Content type matching
  - Track viewed videos (never show same video twice)
  - Recency-based prioritization (0-72h priority)

  NOTE: Videos now stay on platform forever (no 72-hour expiry).
  """

  import Ecto.Query, warn: false
  alias WemachatDatabase.Repo
  alias WemachatDatabase.Schemas.{Video, VideoView, User}

  ## VIDEO VIEWS TRACKING

  @doc """
  Records that a user has watched a video.
  Creates or updates a video view record.

  For featured videos:
  - First view: Creates new record with view_count = 1
  - Re-shows: Increments view_count and updates watched_at
  """
  def record_video_view(user_id, video_id, attrs \\ %{}) do
    attrs = Map.merge(%{user_id: user_id, video_id: video_id}, attrs)

    case get_video_view(user_id, video_id) do
      nil ->
        # First time viewing this video
        %VideoView{}
        |> VideoView.create_changeset(attrs)
        |> Repo.insert()

      existing_view ->
        # Re-viewing a featured video (or updating watch duration)
        # Increment view_count and update watched_at for re-shows
        updated_attrs =
          attrs
          |> Map.put(:view_count, existing_view.view_count + 1)
          |> Map.put(:watched_at, DateTime.utc_now())

        existing_view
        |> VideoView.update_changeset(updated_attrs)
        |> Repo.update()
    end
  end

  @doc """
  Gets a video view record for a user and video.
  """
  def get_video_view(user_id, video_id) do
    VideoView
    |> where([vv], vv.user_id == ^user_id and vv.video_id == ^video_id)
    |> Repo.one()
  end

  @doc """
  Checks if a user has already watched a video.
  """
  def has_viewed?(user_id, video_id) do
    VideoView
    |> where([vv], vv.user_id == ^user_id and vv.video_id == ^video_id)
    |> Repo.exists?()
  end

  @doc """
  Gets list of video IDs that a user has already watched.
  """
  def get_viewed_video_ids(user_id) do
    VideoView
    |> where([vv], vv.user_id == ^user_id)
    |> select([vv], vv.video_id)
    |> Repo.all()
  end

  @doc """
  Gets viewed video data with metadata (view_count, watched_at) for featured video re-show logic.
  Returns a map: %{video_id => %{view_count: n, watched_at: timestamp}}
  """
  def get_viewed_video_metadata(user_id) do
    VideoView
    |> where([vv], vv.user_id == ^user_id)
    |> select([vv], {vv.video_id, %{view_count: vv.view_count, watched_at: vv.watched_at}})
    |> Repo.all()
    |> Map.new()
  end

  ## FOR YOU FEED

  @doc """
  Gets the personalized "For You" feed for a user.
  Uses exclusion-based filtering and admin boost controls.

  Featured videos can re-appear up to 4 times total (1 original + 3 re-shows):
  - Requires 24-hour cooldown between views
  - Scoring decreases with each re-show (100%, 80%, 60%, 40%)

  ## Options
  - `:page` - Page number (default: 1)
  - `:per_page` - Items per page (default: 20)
  - `:include_old` - Include videos older than 72 hours (default: true)
  """
  def get_for_you_feed(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    include_old = Keyword.get(opts, :include_old, true)

    user = Repo.get(User, user_id)

    if user do
      # Get viewed video metadata (includes view_count and watched_at)
      viewed_metadata = get_viewed_video_metadata(user_id)

      # Get blocked user IDs (from contacts context)
      blocked_user_ids = get_blocked_user_ids(user_id)

      # Build base query with exclusions
      query =
        Video
        |> apply_exclusion_filters_with_featured(viewed_metadata, blocked_user_ids)
        |> apply_visibility_filters()
        |> apply_recency_filter(include_old)
        |> apply_geo_targeting(user)
        |> apply_recommendation_scoring_with_reshow(user, viewed_metadata)
        |> order_by([v], desc: v.recommendation_score, desc: v.inserted_at)
        |> limit(^per_page)
        |> offset(^((page - 1) * per_page))

      Repo.all(query)
    else
      []
    end
  end

  ## PATTERN MATCHING FILTERS (Private Functions)

  # Exclusion filters with featured video re-show logic
  # Excludes videos if:
  # - Regular video already viewed, OR
  # - Featured video viewed 4+ times (max reached), OR
  # - Featured video viewed within last 24 hours (cooldown)
  defp apply_exclusion_filters_with_featured(query, viewed_metadata, blocked_user_ids) do
    now = DateTime.utc_now()
    twenty_four_hours_ago = DateTime.add(now, -24, :hour)

    # Build list of video IDs to exclude
    excluded_ids =
      viewed_metadata
      |> Enum.filter(fn {_video_id, metadata} ->
        # Exclude if view_count >= 4 (max re-shows reached)
        metadata.view_count >= 4 or
        # Exclude if last view was within 24 hours (cooldown period)
        DateTime.compare(metadata.watched_at, twenty_four_hours_ago) == :gt
      end)
      |> Enum.map(fn {video_id, _metadata} -> video_id end)

    query
    |> where([v], v.id not in ^excluded_ids)
    |> where([v], v.user_id not in ^blocked_user_ids)
  end

  # OLD: Exclusion filters without featured logic (kept for backward compatibility)
  defp apply_exclusion_filters(query, viewed_ids, blocked_user_ids) do
    query
    |> where([v], v.id not in ^viewed_ids)
    |> where([v], v.user_id not in ^blocked_user_ids)
  end

  # Visibility filters: Only show public, active videos from visible users
  defp apply_visibility_filters(query) do
    query
    |> join(:inner, [v], u in User, on: v.user_id == u.id)
    |> where([v, u], v.visibility_level == "public")
    |> where([v, u], v.is_active == true)
    |> where([v, u], u.is_active == true)
    |> where([v, u], u.is_muted == false)
  end

  # Recency filter: Prioritize recent content (0-72h)
  defp apply_recency_filter(query, include_old) do
    if include_old do
      query
    else
      seventy_two_hours_ago = DateTime.add(DateTime.utc_now(), -72, :hour)
      where(query, [v], v.inserted_at > ^seventy_two_hours_ago)
    end
  end

  # Geo-targeting filter: Only show videos targeted to user's location or untargeted videos
  defp apply_geo_targeting(query, user) do
    query
    |> where([v],
      # Show if not geo-targeted
      (is_nil(v.target_counties) or fragment("array_length(?, 1)", v.target_counties) == 0) or
      # Or if user's county matches
      ^user.location in v.target_counties or
      # Or if user's constituency matches (we'd need to add this field to user schema)
      # ^user.constituency in v.target_constituencies or
      # Or if user's ward matches (we'd need to add this field to user schema)
      # ^user.ward in v.target_wards
      false
    )
  end

  # Recommendation scoring with re-show penalty for featured videos
  # Applies decreasing score multipliers: 100% -> 80% -> 60% -> 40%
  defp apply_recommendation_scoring_with_reshow(query, user, viewed_metadata) do
    user_county = user.location

    # Convert viewed_metadata map to a list for the SQL fragment
    # Format: [[video_id, view_count], ...]
    viewed_list =
      viewed_metadata
      |> Enum.map(fn {video_id, metadata} -> [video_id, metadata.view_count] end)
      |> Jason.encode!()

    query
    |> select_merge([v, u], %{
      recommendation_score:
        fragment(
          """
          (
            (
              -- Base engagement score (0-40 points)
              LEAST(40, (? * 0.01 + ? * 0.1 + ? * 0.2 + ? * 0.05)) +

              -- Recency score (0-30 points)
              CASE
                WHEN ? > NOW() - INTERVAL '24 hours' THEN 30
                WHEN ? > NOW() - INTERVAL '48 hours' THEN 20
                WHEN ? > NOW() - INTERVAL '72 hours' THEN 10
                ELSE 5
              END +

              -- Admin boost score (0-100 points, normalized to 0-30)
              (COALESCE(?, 0) * 0.3) +

              -- User reach multiplier (shadowban/boost)
              (COALESCE(?, 1.0) * 10) +

              -- SILENT PUSH SYSTEM (800-900 points)
              CASE
                WHEN ? = true THEN 900
                WHEN ? = ANY(?) THEN 850
                ELSE 0
              END +

              -- Pinned videos get massive boost (1000 points)
              CASE WHEN ? = true THEN 1000 ELSE 0 END
            )
            -- RE-SHOW PENALTY: Apply multiplier based on view_count
            -- Only applies to featured videos that have been viewed before
            * CASE
                WHEN ? = false THEN 1.0  -- Not featured, no penalty
                ELSE
                  -- Extract view_count from JSON array (if video has been viewed)
                  COALESCE(
                    (
                      SELECT
                        CASE
                          WHEN elem->>1 = '1' THEN 1.0   -- 1st view (100%)
                          WHEN elem->>1 = '2' THEN 0.8   -- 2nd view (80%)
                          WHEN elem->>1 = '3' THEN 0.6   -- 3rd view (60%)
                          WHEN elem->>1 >= '4' THEN 0.4  -- 4th view (40%)
                          ELSE 1.0
                        END
                      FROM jsonb_array_elements(?::jsonb) AS elem
                      WHERE (elem->>0)::uuid = ?
                      LIMIT 1
                    ),
                    1.0  -- Not yet viewed, no penalty
                  )
              END
          )
          """,
          v.views,
          v.likes,
          v.comments,
          v.shares,
          v.inserted_at,
          v.inserted_at,
          v.inserted_at,
          v.admin_boost_score,
          u.reach_multiplier,
          v.push_to_all,
          ^user_county,
          v.push_to_counties,
          v.is_pinned,
          v.is_featured,
          ^viewed_list,
          v.id
        )
    })
  end

  # OLD: Recommendation scoring without re-show logic (kept for backward compatibility)
  defp apply_recommendation_scoring(query, user) do
    user_county = user.location

    query
    |> select_merge([v, u], %{
      recommendation_score:
        fragment(
          """
          (
            -- Base engagement score (0-40 points)
            LEAST(40, (? * 0.01 + ? * 0.1 + ? * 0.2 + ? * 0.05)) +

            -- Recency score (0-30 points)
            CASE
              WHEN ? > NOW() - INTERVAL '24 hours' THEN 30
              WHEN ? > NOW() - INTERVAL '48 hours' THEN 20
              WHEN ? > NOW() - INTERVAL '72 hours' THEN 10
              ELSE 5
            END +

            -- Admin boost score (0-100 points, normalized to 0-30)
            (COALESCE(?, 0) * 0.3) +

            -- User reach multiplier (shadowban/boost)
            (COALESCE(?, 1.0) * 10) +

            -- SILENT PUSH SYSTEM (800-900 points)
            CASE
              WHEN ? = true THEN 900
              WHEN ? = ANY(?) THEN 850
              ELSE 0
            END +

            -- Pinned videos get massive boost (1000 points)
            CASE WHEN ? = true THEN 1000 ELSE 0 END
          )
          """,
          v.views,
          v.likes,
          v.comments,
          v.shares,
          v.inserted_at,
          v.inserted_at,
          v.inserted_at,
          v.admin_boost_score,
          u.reach_multiplier,
          v.push_to_all,
          ^user_county,
          v.push_to_counties,
          v.is_pinned
        )
    })
  end

  # Get blocked user IDs (stub - would integrate with contacts context)
  defp get_blocked_user_ids(_user_id) do
    # TODO: Integrate with WemachatCore.Contexts.Contacts.get_blocked_user_ids(user_id)
    []
  end

  ## ADMIN OPERATIONS

  @doc """
  Updates a video's admin boost score.
  Admin boost score ranges from 0 (no boost) to 100 (maximum boost).
  """
  def set_admin_boost(video_id, boost_score) when boost_score >= 0 and boost_score <= 100 do
    video = Repo.get(Video, video_id)

    if video do
      video
      |> Video.admin_changeset(%{admin_boost_score: boost_score})
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Pins a video (makes it appear first in all feeds).
  """
  def pin_video(video_id) do
    video = Repo.get(Video, video_id)

    if video do
      video
      |> Video.admin_changeset(%{is_pinned: true})
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Unpins a video.
  """
  def unpin_video(video_id) do
    video = Repo.get(Video, video_id)

    if video do
      video
      |> Video.admin_changeset(%{is_pinned: false})
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Sets video visibility level.
  - "public": Normal visibility
  - "limited": Reduced visibility
  - "hidden": Hidden from all feeds
  """
  def set_visibility(video_id, visibility_level)
      when visibility_level in ["public", "limited", "hidden"] do
    video = Repo.get(Video, video_id)

    if video do
      video
      |> Video.admin_changeset(%{visibility_level: visibility_level})
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Sets geo-targeting for a video.
  Pass lists of counties, constituencies, or wards to target.
  Pass empty lists or nil to remove geo-targeting (show to everyone).
  """
  def set_geo_targeting(video_id, opts \\ []) do
    counties = Keyword.get(opts, :counties)
    constituencies = Keyword.get(opts, :constituencies)
    wards = Keyword.get(opts, :wards)

    video = Repo.get(Video, video_id)

    if video do
      attrs = %{}
      attrs = if counties, do: Map.put(attrs, :target_counties, counties), else: attrs
      attrs = if constituencies, do: Map.put(attrs, :target_constituencies, constituencies), else: attrs
      attrs = if wards, do: Map.put(attrs, :target_wards, wards), else: attrs

      video
      |> Video.admin_changeset(attrs)
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  ## SILENT PUSH SYSTEM

  @doc """
  Activates push to all for a video (silently promotes to everyone).
  Sets push_to_all to true and records pushed_at timestamp.
  No user notifications are sent - feed just prioritizes this video.
  """
  def activate_push_to_all(video_id) do
    video = Repo.get(Video, video_id)

    if video do
      video
      |> Video.admin_changeset(%{
        push_to_all: true,
        pushed_at: DateTime.utc_now()
      })
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Deactivates push to all for a video.
  """
  def deactivate_push_to_all(video_id) do
    video = Repo.get(Video, video_id)

    if video do
      video
      |> Video.admin_changeset(%{push_to_all: false})
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Sets location-based silent push for a video.
  Push precedence: push_to_all > push_to_counties > push_to_constituencies > push_to_wards

  ## Options
  - `:counties` - List of county names to push to
  - `:constituencies` - List of constituency names to push to
  - `:wards` - List of ward names to push to

  Pass empty lists to clear targeting.
  """
  def set_push_targeting(video_id, opts \\ []) do
    counties = Keyword.get(opts, :counties)
    constituencies = Keyword.get(opts, :constituencies)
    wards = Keyword.get(opts, :wards)

    video = Repo.get(Video, video_id)

    if video do
      attrs = %{}
      attrs = if counties, do: Map.put(attrs, :push_to_counties, counties), else: attrs
      attrs = if constituencies, do: Map.put(attrs, :push_to_constituencies, constituencies), else: attrs
      attrs = if wards, do: Map.put(attrs, :push_to_wards, wards), else: attrs

      # Only set pushed_at if we're actually pushing to somewhere
      has_push_target =
        (counties && length(counties) > 0) ||
        (constituencies && length(constituencies) > 0) ||
        (wards && length(wards) > 0)

      attrs = if has_push_target, do: Map.put(attrs, :pushed_at, DateTime.utc_now()), else: attrs

      video
      |> Video.admin_changeset(attrs)
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Clears all push settings for a video (stops silent promotion).
  """
  def clear_all_push(video_id) do
    video = Repo.get(Video, video_id)

    if video do
      video
      |> Video.admin_changeset(%{
        push_to_all: false,
        push_to_counties: [],
        push_to_constituencies: [],
        push_to_wards: []
      })
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  ## USER MODERATION (Pattern Matching Examples)

  @doc """
  Mutes a user (hides all their content from recommendations).
  Uses pattern matching to handle different user states.
  """
  def mute_user(user_id) do
    case Repo.get(User, user_id) do
      %User{is_muted: true} = user ->
        # Already muted, return as-is
        {:ok, user}

      %User{} = user ->
        # Mute the user
        user
        |> User.moderation_changeset(%{is_muted: true})
        |> Repo.update()

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Unmutes a user.
  """
  def unmute_user(user_id) do
    case Repo.get(User, user_id) do
      %User{is_muted: false} = user ->
        # Already unmuted
        {:ok, user}

      %User{} = user ->
        user
        |> User.moderation_changeset(%{is_muted: false})
        |> Repo.update()

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Shadowbans a user (drastically reduces their reach without notifying them).
  Sets reach_multiplier to 0.1 (10% normal reach).
  """
  def shadowban_user(user_id) do
    case Repo.get(User, user_id) do
      %User{is_shadowbanned: true} = user ->
        # Already shadowbanned
        {:ok, user}

      %User{} = user ->
        user
        |> User.moderation_changeset(%{
          is_shadowbanned: true,
          reach_multiplier: Decimal.new("0.1")
        })
        |> Repo.update()

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Removes shadowban from a user (restores normal reach).
  """
  def unshadowban_user(user_id) do
    case Repo.get(User, user_id) do
      %User{is_shadowbanned: false} = user ->
        # Not shadowbanned
        {:ok, user}

      %User{} = user ->
        user
        |> User.moderation_changeset(%{
          is_shadowbanned: false,
          reach_multiplier: Decimal.new("1.0")
        })
        |> Repo.update()

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Sets a user's reach multiplier (0.0 to 2.0).
  - 0.0 = no reach (shadowban)
  - 1.0 = normal reach
  - 2.0 = double reach (boost)
  """
  def set_reach_multiplier(user_id, multiplier)
      when is_number(multiplier) and multiplier >= 0.0 and multiplier <= 2.0 do
    case Repo.get(User, user_id) do
      %User{} = user ->
        user
        |> User.moderation_changeset(%{reach_multiplier: Decimal.new(to_string(multiplier))})
        |> Repo.update()

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Sets a user's creator content type (what they create).
  """
  def set_creator_content_type(user_id, content_type)
      when content_type in [
        "comedy", "music", "education", "news", "lifestyle",
        "sports", "technology", "fashion", "food", "travel",
        "entertainment", "business", "health", "politics", "other"
      ] do
    case Repo.get(User, user_id) do
      %User{} = user ->
        user
        |> User.moderation_changeset(%{creator_content_type: content_type})
        |> Repo.update()

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Sets a user's interest type (what they watch).
  """
  def set_interest_type(user_id, content_type)
      when content_type in [
        "comedy", "music", "education", "news", "lifestyle",
        "sports", "technology", "fashion", "food", "travel",
        "entertainment", "business", "health", "politics", "other"
      ] do
    case Repo.get(User, user_id) do
      %User{} = user ->
        user
        |> User.moderation_changeset(%{interest_type: content_type})
        |> Repo.update()

      nil ->
        {:error, :not_found}
    end
  end
end
