defmodule WemachatCore.Contexts.Statuses do
  @moduledoc """
  The Statuses context.
  Handles all business logic for WhatsApp-like status feature with 24-hour auto-expiry.
  """

  import Ecto.Query, warn: false
  alias WemachatDatabase.Repo
  alias WemachatDatabase.Schemas.{Status, StatusView, StatusLike}
  alias WemachatCore.Contexts.Users

  ## CREATE

  @doc """
  Creates a status. Automatically sets expires_at to 24 hours from now.
  """
  def create_status(attrs \\ %{}) do
    %Status{}
    |> Status.create_changeset(attrs)
    |> Repo.insert()
  end

  ## READ

  @doc """
  Gets a single status by ID.
  Returns nil if status doesn't exist or is expired/deleted.
  """
  def get_status(id) do
    now = DateTime.utc_now()

    Status
    |> where([s], s.id == ^id)
    |> where([s], s.is_deleted == false)
    |> where([s], s.expires_at > ^now)
    |> Repo.one()
  end

  @doc """
  Gets a single status by ID, raises if not found or expired.
  """
  def get_status!(id) do
    now = DateTime.utc_now()

    Status
    |> where([s], s.id == ^id)
    |> where([s], s.is_deleted == false)
    |> where([s], s.expires_at > ^now)
    |> Repo.one!()
  end

  @doc """
  Lists all active statuses for a specific user.
  Returns only non-expired, non-deleted statuses.
  """
  def list_user_statuses(user_id, opts \\ []) do
    now = DateTime.utc_now()
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    Status
    |> where([s], s.user_id == ^user_id)
    |> where([s], s.is_deleted == false)
    |> where([s], s.expires_at > ^now)
    |> order_by([s], desc: s.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Lists all active statuses grouped by user (for status feed).
  Returns list of maps with user info and their statuses.
  Applies privacy filters based on viewer_id.

  Returns: [
    %{
      user_id: "user123",
      user_name: "John Doe",
      user_avatar: "https://...",
      status_count: 3,
      latest_status_at: ~U[2025-11-17 12:00:00.000000Z],
      statuses: [%Status{}, ...]
    }
  ]
  """
  def list_all_statuses(viewer_id, opts \\ []) do
    now = DateTime.utc_now()
    _page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    # Get all active statuses that the viewer can see
    statuses =
      Status
      |> where([s], s.is_deleted == false)
      |> where([s], s.expires_at > ^now)
      |> where([s], s.user_id != ^viewer_id)  # Don't include viewer's own statuses here
      |> apply_visibility_filter(viewer_id)
      |> order_by([s], desc: s.inserted_at)
      |> Repo.all()

    # Group by user_id
    statuses
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {user_id, user_statuses} ->
      # Get user info
      user = Users.get_user(user_id)

      %{
        user_id: user_id,
        user_name: if(user, do: user.name, else: "Unknown User"),
        user_avatar: if(user, do: user.profile_image, else: nil),
        status_count: length(user_statuses),
        latest_status_at: hd(user_statuses).inserted_at,
        statuses: user_statuses
      }
    end)
    |> Enum.sort_by(& &1.latest_status_at, {:desc, DateTime})
    |> Enum.take(per_page)
  end

  ## UPDATE

  @doc """
  Soft deletes a status (only owner can delete).
  """
  def delete_status(status_id, user_id) do
    case get_status(status_id) do
      nil ->
        {:error, :not_found}

      status ->
        if status.user_id == user_id do
          status
          |> Status.delete_changeset()
          |> Repo.update()
        else
          {:error, :unauthorized}
        end
    end
  end

  @doc """
  Records a status view.
  Creates a view record and increments the count (via database trigger).
  Prevents duplicate views from the same user.
  """
  def view_status(status_id, viewer_id) do
    attrs = %{
      status_id: status_id,
      user_id: viewer_id
    }

    case get_status(status_id) do
      nil ->
        {:error, :not_found}

      status ->
        # Check if user can view this status
        if Status.visible_to_user?(status, viewer_id) do
          %StatusView{}
          |> StatusView.create_changeset(attrs)
          |> Repo.insert(
            on_conflict: {:replace, [:viewed_at, :updated_at]},
            conflict_target: [:status_id, :user_id]
          )
        else
          {:error, :forbidden}
        end
    end
  end

  @doc """
  Likes a status.
  Creates a like record and increments the count (via database trigger).
  """
  def like_status(status_id, user_id) do
    attrs = %{
      status_id: status_id,
      user_id: user_id
    }

    case get_status(status_id) do
      nil ->
        {:error, :not_found}

      status ->
        # Check if user can view this status
        if Status.visible_to_user?(status, user_id) do
          %StatusLike{}
          |> StatusLike.create_changeset(attrs)
          |> Repo.insert()
        else
          {:error, :forbidden}
        end
    end
  end

  @doc """
  Unlikes a status.
  Removes the like record and decrements the count (via database trigger).
  """
  def unlike_status(status_id, user_id) do
    StatusLike
    |> where([l], l.status_id == ^status_id and l.user_id == ^user_id)
    |> Repo.delete_all()
    |> case do
      {0, _} -> {:error, :not_found}
      {1, _} -> {:ok, :deleted}
      _ -> {:error, :unknown}
    end
  end

  @doc """
  Checks if a user has liked a status.
  """
  def liked_by_user?(status_id, user_id) do
    StatusLike
    |> where([l], l.status_id == ^status_id and l.user_id == ^user_id)
    |> Repo.exists?()
  end

  ## CLEANUP

  @doc """
  Deletes all expired statuses (cleanup job).
  This should be run periodically by a background job.
  """
  def cleanup_expired do
    now = DateTime.utc_now()

    {count, _} =
      Status
      |> where([s], s.expires_at <= ^now)
      |> Repo.delete_all()

    {:ok, count}
  end

  ## PRIVATE HELPERS

  # Apply visibility filters to the query
  defp apply_visibility_filter(query, viewer_id) do
    query
    |> where(
      [s],
      # Show if visibility is "all" and viewer is not in hidden_from list
      (s.visibility == "all" and fragment("NOT (? = ANY(?))", ^viewer_id, s.hidden_from)) or
        # Show if visibility is "custom" and viewer is in visible_to list
        (s.visibility == "custom" and fragment("? = ANY(?)", ^viewer_id, s.visible_to)) or
        # Show if visibility is "close_friends" (actual close friends check should be done at application level)
        s.visibility == "close_friends"
    )
  end

  @doc """
  Get status with user information.
  """
  def get_status_with_user(status_id) do
    case get_status(status_id) do
      nil ->
        nil

      status ->
        user = Users.get_user(status.user_id)

        status
        |> Map.put(:user_name, if(user, do: user.name, else: "Unknown User"))
        |> Map.put(:user_avatar, if(user, do: user.profile_image, else: nil))
    end
  end

  @doc """
  Enrich statuses with user information.
  """
  def enrich_statuses_with_user_info(statuses) when is_list(statuses) do
    Enum.map(statuses, fn status ->
      user = Users.get_user(status.user_id)

      status
      |> Map.put(:user_name, if(user, do: user.name, else: "Unknown User"))
      |> Map.put(:user_avatar, if(user, do: user.profile_image, else: nil))
    end)
  end

  def enrich_statuses_with_user_info(status) when is_map(status) do
    user = Users.get_user(status.user_id)

    status
    |> Map.put(:user_name, if(user, do: user.name, else: "Unknown User"))
    |> Map.put(:user_avatar, if(user, do: user.profile_image, else: nil))
  end
end
