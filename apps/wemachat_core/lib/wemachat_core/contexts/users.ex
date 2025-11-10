defmodule WemachatCore.Contexts.Users do
  @moduledoc """
  The Users context.
  Handles all business logic for user management, profiles, and authentication.
  """

  import Ecto.Query, warn: false
  alias WemachatDatabase.Repo
  alias WemachatDatabase.Schemas.User
  alias WemachatCore.Contexts.Wallets

  ## CREATE

  @doc """
  Creates a new user from Firebase authentication.
  Called when a user first signs up with Firebase phone auth.
  Automatically creates a wallet for the new user.
  """
  def create_user(attrs \\ %{}) do
    # Use transaction to ensure user and wallet are created together
    Repo.transaction(fn ->
      # Create the user
      case %User{}
           |> User.create_changeset(attrs)
           |> Repo.insert() do
        {:ok, user} ->
          # Automatically create wallet for new user
          case Wallets.get_or_create_wallet(user.id) do
            {:ok, _wallet} -> user
            {:error, reason} ->
              # Rollback transaction if wallet creation fails
              Repo.rollback(reason)
          end

        {:error, changeset} ->
          # Rollback transaction if user creation fails
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Finds or creates a user by Firebase UID.
  This is the main sync function for Firebase auth.
  Ensures user has a wallet (creates one if missing).
  """
  def find_or_create_user(firebase_uid, attrs \\ %{}) do
    case get_user(firebase_uid) do
      nil ->
        # Create new user (which will automatically create wallet)
        attrs_with_id = Map.put(attrs, "id", firebase_uid)
        create_user(attrs_with_id)

      user ->
        # User exists, ensure they have a wallet
        # This handles legacy users who were created before automatic wallet creation
        case Wallets.get_or_create_wallet(user.id) do
          {:ok, _wallet} -> {:ok, user}
          {:error, _reason} -> {:ok, user}  # Don't fail if wallet creation fails
        end
    end
  end

  ## READ

  @doc """
  Gets a single user by Firebase UID.
  Returns nil if the user does not exist.
  """
  def get_user(id) do
    Repo.get(User, id)
  end

  @doc """
  Gets a single user by Firebase UID.
  Raises Ecto.NoResultsError if the User does not exist.
  """
  def get_user!(id) do
    Repo.get!(User, id)
  end

  @doc """
  Gets a user by phone number.
  """
  def get_user_by_phone(phone_number) do
    Repo.get_by(User, phone_number: phone_number)
  end

  @doc """
  Lists all users with pagination.
  """
  def list_users(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    User
    |> order_by([u], desc: u.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Lists verified users.
  """
  def list_verified_users(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    User
    |> where([u], u.is_verified == true)
    |> order_by([u], desc: u.followers_count)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Lists featured users.
  """
  def list_featured_users(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    User
    |> where([u], u.is_featured == true)
    |> order_by([u], desc: u.followers_count)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Lists users who are currently live streaming.
  """
  def list_live_users do
    User
    |> where([u], u.is_live == true)
    |> order_by([u], desc: u.followers_count)
    |> Repo.all()
  end

  @doc """
  Search users by name or bio (full-text search).
  """
  def search_users(query, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    search_query = "%#{query}%"

    User
    |> where([u], ilike(u.name, ^search_query) or ilike(u.bio, ^search_query))
    |> order_by([u], desc: u.followers_count)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Gets users by a list of UIDs (bulk fetch).
  """
  def get_users_by_ids(ids) when is_list(ids) do
    User
    |> where([u], u.id in ^ids)
    |> Repo.all()
  end

  ## UPDATE

  @doc """
  Updates a user's profile.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a user's last_seen timestamp.
  Called when a user opens the app or performs an action.
  """
  def update_last_seen(%User{} = user) do
    user
    |> User.last_seen_changeset()
    |> Repo.update()
  end

  @doc """
  Updates a user's live streaming status.
  """
  def update_live_status(%User{} = user, is_live) do
    user
    |> User.live_status_changeset(is_live)
    |> Repo.update()
  end

  @doc """
  Admin function: Update user roles and permissions.
  """
  def admin_update_user(%User{} = user, attrs) do
    user
    |> User.admin_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Increment follower count (called when someone follows this user).
  """
  def increment_followers(%User{} = user) do
    user
    |> Ecto.Changeset.change(followers_count: user.followers_count + 1)
    |> Repo.update()
  end

  @doc """
  Decrement follower count (called when someone unfollows this user).
  """
  def decrement_followers(%User{} = user) do
    new_count = max(0, user.followers_count - 1)

    user
    |> Ecto.Changeset.change(followers_count: new_count)
    |> Repo.update()
  end

  @doc """
  Increment following count (called when this user follows someone).
  """
  def increment_following(%User{} = user) do
    user
    |> Ecto.Changeset.change(following_count: user.following_count + 1)
    |> Repo.update()
  end

  @doc """
  Decrement following count (called when this user unfollows someone).
  """
  def decrement_following(%User{} = user) do
    new_count = max(0, user.following_count - 1)

    user
    |> Ecto.Changeset.change(following_count: new_count)
    |> Repo.update()
  end

  @doc """
  Increment videos count (called when user posts a video).
  """
  def increment_videos(%User{} = user) do
    now = DateTime.utc_now()

    user
    |> Ecto.Changeset.change(
      videos_count: user.videos_count + 1,
      last_post_at: now
    )
    |> Repo.update()
  end

  @doc """
  Decrement videos count (called when user deletes a video).
  """
  def decrement_videos(%User{} = user) do
    new_count = max(0, user.videos_count - 1)

    user
    |> Ecto.Changeset.change(videos_count: new_count)
    |> Repo.update()
  end

  ## DELETE

  @doc """
  Soft deletes a user (sets is_active to false).
  """
  def deactivate_user(%User{} = user) do
    user
    |> Ecto.Changeset.change(is_active: false)
    |> Repo.update()
  end

  @doc """
  Hard deletes a user (permanent removal from database).
  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  ## FOLLOW SYSTEM

  @doc """
  Add a follower to a user's follower list.
  """
  def add_follower(%User{} = user, follower_uid) do
    if follower_uid in user.follower_uids do
      {:ok, user}
    else
      user
      |> Ecto.Changeset.change(follower_uids: [follower_uid | user.follower_uids])
      |> Repo.update()
      |> case do
        {:ok, updated_user} ->
          increment_followers(updated_user)

        error ->
          error
      end
    end
  end

  @doc """
  Remove a follower from a user's follower list.
  """
  def remove_follower(%User{} = user, follower_uid) do
    if follower_uid in user.follower_uids do
      user
      |> Ecto.Changeset.change(
        follower_uids: List.delete(user.follower_uids, follower_uid)
      )
      |> Repo.update()
      |> case do
        {:ok, updated_user} ->
          decrement_followers(updated_user)

        error ->
          error
      end
    else
      {:ok, user}
    end
  end

  @doc """
  Add a user to the following list.
  """
  def add_following(%User{} = user, following_uid) do
    if following_uid in user.following_uids do
      {:ok, user}
    else
      user
      |> Ecto.Changeset.change(following_uids: [following_uid | user.following_uids])
      |> Repo.update()
      |> case do
        {:ok, updated_user} ->
          increment_following(updated_user)

        error ->
          error
      end
    end
  end

  @doc """
  Remove a user from the following list.
  """
  def remove_following(%User{} = user, following_uid) do
    if following_uid in user.following_uids do
      user
      |> Ecto.Changeset.change(
        following_uids: List.delete(user.following_uids, following_uid)
      )
      |> Repo.update()
      |> case do
        {:ok, updated_user} ->
          decrement_following(updated_user)

        error ->
          error
      end
    else
      {:ok, user}
    end
  end

  @doc """
  Check if user is following another user.
  """
  def following?(%User{} = user, other_user_uid) do
    other_user_uid in user.following_uids
  end

  @doc """
  Get list of user IDs that the user is following.
  """
  def get_following_ids(user_id) do
    case get_user(user_id) do
      nil -> []
      user -> user.following_uids || []
    end
  end

  ## STATISTICS

  @doc """
  Gets total user count.
  """
  def count_users do
    Repo.aggregate(User, :count)
  end

  @doc """
  Gets active user count.
  """
  def count_active_users do
    User
    |> where([u], u.is_active == true)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets verified user count.
  """
  def count_verified_users do
    User
    |> where([u], u.is_verified == true)
    |> Repo.aggregate(:count)
  end
end
