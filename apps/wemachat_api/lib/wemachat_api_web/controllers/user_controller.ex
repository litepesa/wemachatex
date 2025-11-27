defmodule WemachatApiWeb.UserController do
  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.Users
  alias WemachatApiWeb.Plugs.FirebaseAuth

  # Apply Firebase auth to protected routes
  plug FirebaseAuth when action not in [:index, :show, :search]

  @doc """
  POST /api/v1/users/sync
  Sync user from Firebase authentication (find or create).
  """
  def sync(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)

    # Convert camelCase params from Flutter to snake_case for Ecto
    snake_case_params = transform_params_to_snake_case(params)

    case Users.find_or_create_user(user_id, snake_case_params) do
      {:ok, user} ->
        conn
        |> put_status(:ok)
        |> json(format_user(user))

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to sync user", details: format_errors(changeset)})
    end
  end

  @doc """
  GET /api/v1/users
  List users with pagination.
  """
  def index(conn, params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    users = Users.list_users(page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      users: Enum.map(users, &format_user/1),
      page: page,
      per_page: per_page
    })
  end

  @doc """
  GET /api/v1/users/verified
  List verified users.
  """
  def verified(conn, params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    users = Users.list_verified_users(page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      users: Enum.map(users, &format_user/1),
      page: page,
      per_page: per_page
    })
  end

  @doc """
  GET /api/v1/users/featured
  List featured users.
  """
  def featured(conn, params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    users = Users.list_featured_users(page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      users: Enum.map(users, &format_user/1),
      page: page,
      per_page: per_page
    })
  end

  @doc """
  GET /api/v1/users/live
  List users who are currently live streaming.
  """
  def live(conn, _params) do
    users = Users.list_live_users()

    conn
    |> put_status(:ok)
    |> json(%{users: Enum.map(users, &format_user/1)})
  end

  @doc """
  GET /api/v1/users/search?q=query
  Search users by name or bio.
  """
  def search(conn, %{"q" => query} = params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    users = Users.search_users(query, page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      users: Enum.map(users, &format_user/1),
      page: page,
      per_page: per_page,
      query: query
    })
  end

  def search(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing search query parameter 'q'"})
  end

  @doc """
  GET /api/v1/users/:id
  Get a single user by ID.
  """
  def show(conn, %{"id" => id}) do
    case Users.get_user(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})

      user ->
        conn
        |> put_status(:ok)
        |> json(format_user(user))
    end
  end

  @doc """
  PUT /api/v1/users/:id
  Update user profile (authenticated users only).
  """
  def update(conn, %{"id" => id} = params) do
    current_user_id = FirebaseAuth.current_user_id(conn)

    # Users can only update their own profile (unless admin)
    if id != current_user_id do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "You can only update your own profile"})
    else
      case Users.get_user(id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "User not found"})

        user ->
          case Users.update_user(user, params) do
            {:ok, updated_user} ->
              conn
              |> put_status(:ok)
              |> json(format_user(updated_user))

            {:error, changeset} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Failed to update user", details: format_errors(changeset)})
          end
      end
    end
  end

  @doc """
  POST /api/v1/users/:id/follow
  Follow a user (authenticated users only).
  """
  def follow(conn, %{"id" => target_user_id}) do
    current_user_id = FirebaseAuth.current_user_id(conn)

    # Can't follow yourself
    if target_user_id == current_user_id do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "You cannot follow yourself"})
    else
      current_user = Users.get_user(current_user_id)
      target_user = Users.get_user(target_user_id)

      cond do
        is_nil(current_user) ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Current user not found"})

        is_nil(target_user) ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Target user not found"})

        Users.following?(current_user, target_user_id) ->
          conn
          |> put_status(:ok)
          |> json(%{message: "Already following this user"})

        true ->
          # Add to current user's following list
          with {:ok, _} <- Users.add_following(current_user, target_user_id),
               {:ok, _} <- Users.add_follower(target_user, current_user_id) do
            conn
            |> put_status(:ok)
            |> json(%{message: "Successfully followed user"})
          else
            {:error, _} ->
              conn
              |> put_status(:internal_server_error)
              |> json(%{error: "Failed to follow user"})
          end
      end
    end
  end

  @doc """
  DELETE /api/v1/users/:id/follow
  Unfollow a user (authenticated users only).
  """
  def unfollow(conn, %{"id" => target_user_id}) do
    current_user_id = FirebaseAuth.current_user_id(conn)

    current_user = Users.get_user(current_user_id)
    target_user = Users.get_user(target_user_id)

    cond do
      is_nil(current_user) ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Current user not found"})

      is_nil(target_user) ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Target user not found"})

      not Users.following?(current_user, target_user_id) ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Not following this user"})

      true ->
        # Remove from current user's following list
        with {:ok, _} <- Users.remove_following(current_user, target_user_id),
             {:ok, _} <- Users.remove_follower(target_user, current_user_id) do
          conn
          |> put_status(:ok)
          |> json(%{message: "Successfully unfollowed user"})
        else
          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to unfollow user"})
        end
    end
  end

  @doc """
  PUT /api/v1/users/:id/live
  Update live streaming status (authenticated users only).
  """
  def update_live_status(conn, %{"id" => id, "is_live" => is_live}) do
    current_user_id = FirebaseAuth.current_user_id(conn)

    # Users can only update their own live status
    if id != current_user_id do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "You can only update your own live status"})
    else
      case Users.get_user(id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "User not found"})

        user ->
          case Users.update_live_status(user, is_live) do
            {:ok, updated_user} ->
              conn
              |> put_status(:ok)
              |> json(format_user(updated_user))

            {:error, _} ->
              conn
              |> put_status(:internal_server_error)
              |> json(%{error: "Failed to update live status"})
          end
      end
    end
  end

  # Helper Functions

  defp format_user(user) do
    %{
      uid: user.id,
      id: user.id,
      phoneNumber: user.phone_number,
      phone_number: user.phone_number,
      mpesaNumber: user.mpesa_number,
      mpesa_number: user.mpesa_number,
      name: user.name,
      bio: user.bio,
      profileImage: user.profile_image,
      profile_image: user.profile_image,
      coverImage: user.cover_image,
      cover_image: user.cover_image,
      followersCount: user.followers_count,
      followers_count: user.followers_count,
      followingCount: user.following_count,
      following_count: user.following_count,
      videosCount: user.videos_count,
      videos_count: user.videos_count,
      likesCount: user.likes_count,
      likes_count: user.likes_count,
      isVerified: user.is_verified,
      is_verified: user.is_verified,
      isActive: user.is_active,
      is_active: user.is_active,
      isFeatured: user.is_featured,
      is_featured: user.is_featured,
      isLive: user.is_live,
      is_live: user.is_live,
      isAdmin: user.is_admin,
      is_admin: user.is_admin,
      isModerator: user.is_moderator,
      is_moderator: user.is_moderator,
      canComment: user.can_comment,
      can_comment: user.can_comment,
      canPost: user.can_post,
      can_post: user.can_post,
      gender: user.gender,
      location: user.location,
      language: user.language,
      tags: user.tags,
      followerUIDs: user.follower_uids,
      follower_uids: user.follower_uids,
      followingUIDs: user.following_uids,
      following_uids: user.following_uids,
      likedVideos: user.liked_videos,
      liked_videos: user.liked_videos,
      preferences: user.preferences,
      lastSeen: user.last_seen,
      last_seen: user.last_seen,
      lastPostAt: user.last_post_at,
      last_post_at: user.last_post_at,
      createdAt: user.inserted_at,
      created_at: user.inserted_at,
      updatedAt: user.updated_at,
      updated_at: user.updated_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(_, default), do: default

  @doc """
  Transforms camelCase parameter keys to snake_case for Ecto.
  Recursively handles nested maps (like preferences).
  Also truncates datetime strings to remove microseconds.
  """
  defp transform_params_to_snake_case(params) when is_map(params) do
    params
    |> Enum.map(fn {key, value} ->
      snake_key = camel_to_snake(key)
      # Recursively transform nested maps (but don't modify datetime strings)
      transformed_value = if is_map(value), do: transform_params_to_snake_case(value), else: value
      {snake_key, transformed_value}
    end)
    |> Enum.into(%{})
  end

  defp transform_params_to_snake_case(params), do: params

  # Check if a string is an ISO8601 datetime
  defp is_datetime_string?(value) when is_binary(value) do
    String.match?(value, ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
  end
  defp is_datetime_string?(_), do: false

  # Keep datetime string as-is (don't truncate microseconds)
  # Ecto expects :utc_datetime_usec with microsecond precision
  defp truncate_datetime_string(datetime_str) when is_binary(datetime_str) do
    datetime_str
  end
  defp truncate_datetime_string(value), do: value

  @doc """
  Converts a camelCase string to snake_case.
  Examples:
    - "phoneNumber" -> "phone_number"
    - "profileImage" -> "profile_image"
    - "isVerified" -> "is_verified"
  """
  defp camel_to_snake(string) when is_binary(string) do
    string
    |> String.replace(~r/([A-Z])/, "_\\1")
    |> String.downcase()
    |> String.trim_leading("_")
  end

  defp camel_to_snake(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> camel_to_snake()
  end

  defp camel_to_snake(other), do: other
end
