defmodule WemachatApiWeb.ChannelController do
  @moduledoc """
  Controller for broadcast channels CRUD and subscriptions.
  """
  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.Channels
  alias WemachatApiWeb.Plugs.FirebaseAuth

  plug FirebaseAuth

  ## CHANNEL CRUD

  @doc """
  GET /api/v1/channels/check-name?name=MyChannel
  Check if a channel name is available.
  """
  def check_name(conn, %{"name" => name}) do
    is_available = Channels.is_channel_name_available?(name)

    conn
    |> put_status(:ok)
    |> json(%{
      available: is_available,
      name: String.trim(name),
      message: if(is_available, do: "This name is available", else: "This name is already taken")
    })
  end

  @doc """
  GET /api/v1/channels
  List channels with optional filters: ?type=public&page=1&per_page=20&search=query
  """
  def index(conn, params) do
    opts = [
      page: String.to_integer(params["page"] || "1"),
      per_page: String.to_integer(params["per_page"] || "20"),
      type: params["type"],
      search: params["search"]
    ]

    channels = Channels.list_channels(opts)

    conn
    |> put_status(:ok)
    |> json(%{channels: Enum.map(channels, &format_channel/1)})
  end

  @doc """
  GET /api/v1/channels/trending
  List trending channels (sorted by subscriber count).
  """
  def trending(conn, params) do
    limit = String.to_integer(params["limit"] || "10")
    channels = Channels.list_trending_channels(limit: limit)

    conn
    |> put_status(:ok)
    |> json(%{channels: Enum.map(channels, &format_channel/1)})
  end

  @doc """
  GET /api/v1/channels/subscribed
  List channels the current user is subscribed to.
  """
  def subscribed(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)

    opts = [
      page: String.to_integer(params["page"] || "1"),
      per_page: String.to_integer(params["per_page"] || "20")
    ]

    channels = Channels.list_subscribed_channels(user_id, opts)

    conn
    |> put_status(:ok)
    |> json(%{channels: Enum.map(channels, &format_channel/1)})
  end

  @doc """
  GET /api/v1/channels/:id
  Get a single channel by ID.
  """
  def show(conn, %{"id" => id}) do
    case Channels.get_channel(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Channel not found"})

      channel ->
        user_id = FirebaseAuth.current_user_id(conn)
        is_subscribed = Channels.is_subscribed?(channel.id, user_id)
        is_owner = Channels.is_channel_owner?(channel.id, user_id)
        is_member = Channels.is_channel_member?(channel.id, user_id)

        # Get member role to determine admin status (only admin role exists, no moderator)
        member = Channels.get_channel_member(channel.id, user_id)
        is_admin = member && member.role == :admin

        subscription = Channels.get_subscription(channel.id, user_id)

        conn
        |> put_status(:ok)
        |> json(%{
          channel: format_channel(channel),
          isSubscribed: is_subscribed,
          is_subscribed: is_subscribed,
          isOwner: is_owner,
          is_owner: is_owner,
          isAdmin: is_admin,
          is_admin: is_admin,
          isMember: is_member,
          is_member: is_member,
          unreadCount: if(subscription, do: subscription.unread_count, else: 0),
          unread_count: if(subscription, do: subscription.unread_count, else: 0)
        })
    end
  end

  @doc """
  POST /api/v1/channels
  Create a new channel.
  Body: {name, description, type, subscriptionPriceCoins?, avatarUrl?, bannerUrl?}
  """
  def create(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)

    attrs = %{
      "name" => params["name"],
      "description" => params["description"],
      "owner_id" => user_id,
      "type" => params["type"] || "public",
      "subscription_price_coins" => params["subscriptionPriceCoins"] || params["subscription_price_coins"],
      "avatar_url" => params["avatarUrl"] || params["avatar_url"],
      "banner_url" => params["bannerUrl"] || params["banner_url"]
    }

    case Channels.create_channel(attrs) do
      {:ok, channel} ->
        conn
        |> put_status(:created)
        |> json(%{channel: format_channel(channel)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create channel", errors: format_errors(changeset)})
    end
  end

  @doc """
  PUT /api/v1/channels/:id
  Update channel information (owner only).
  Body: {name?, description?, avatarUrl?, bannerUrl?}
  """
  def update(conn, %{"id" => id} = params) do
    user_id = FirebaseAuth.current_user_id(conn)

    with channel when not is_nil(channel) <- Channels.get_channel(id),
         true <- Channels.is_channel_owner?(id, user_id) do
      attrs = %{
        "name" => params["name"],
        "description" => params["description"],
        "avatar_url" => params["avatarUrl"] || params["avatar_url"],
        "banner_url" => params["bannerUrl"] || params["banner_url"]
      }

      case Channels.update_channel(channel, attrs) do
        {:ok, updated_channel} ->
          conn
          |> put_status(:ok)
          |> json(%{channel: format_channel(updated_channel)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to update channel", errors: format_errors(changeset)})
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Channel not found"})

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only channel owner can update"})
    end
  end

  @doc """
  DELETE /api/v1/channels/:id
  Delete a channel (owner only).
  """
  def delete(conn, %{"id" => id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    with channel when not is_nil(channel) <- Channels.get_channel(id),
         true <- Channels.is_channel_owner?(id, user_id) do
      case Channels.delete_channel(channel) do
        {:ok, _} ->
          conn
          |> put_status(:ok)
          |> json(%{message: "Channel deleted successfully"})

        {:error, _} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to delete channel"})
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Channel not found"})

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only channel owner can delete"})
    end
  end

  ## SUBSCRIPTIONS

  @doc """
  POST /api/v1/channels/:id/subscribe
  Subscribe to a channel.
  """
  def subscribe(conn, %{"id" => channel_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Channels.subscribe_to_channel(channel_id, user_id) do
      {:ok, subscription} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Subscribed successfully",
          subscription: format_subscription(subscription)
        })

      {:error, %{errors: [channel_id: {"user is already a member of this channel", _}]}} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Already subscribed"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to subscribe"})
    end
  end

  @doc """
  DELETE /api/v1/channels/:id/subscribe
  Unsubscribe from a channel.
  """
  def unsubscribe(conn, %{"id" => channel_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Channels.unsubscribe_from_channel(channel_id, user_id) do
      {:ok, _} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Unsubscribed successfully"})

      {:error, :not_subscribed} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Not subscribed to this channel"})

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to unsubscribe"})
    end
  end

  @doc """
  POST /api/v1/channels/:id/mark-read
  Mark all posts in a channel as read.
  """
  def mark_read(conn, %{"id" => channel_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Channels.mark_channel_as_read(channel_id, user_id) do
      {:ok, subscription} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Marked as read",
          subscription: format_subscription(subscription)
        })

      {:error, :not_subscribed} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Not subscribed to this channel"})

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to mark as read"})
    end
  end

  @doc """
  POST /api/v1/channels/:id/notifications
  Toggle notification preferences.
  Body: {enabled: boolean}
  """
  def toggle_notifications(conn, %{"id" => channel_id} = params) do
    user_id = FirebaseAuth.current_user_id(conn)
    enabled = params["enabled"] || false

    case Channels.toggle_notifications(channel_id, user_id, enabled) do
      {:ok, subscription} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Notifications #{if enabled, do: "enabled", else: "disabled"}",
          subscription: format_subscription(subscription)
        })

      {:error, :not_subscribed} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Not subscribed to this channel"})

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to update notifications"})
    end
  end

  ## CHANNEL MEMBERS

  @doc """
  GET /api/v1/channels/:id/members
  List channel members (admins/moderators).
  """
  def list_members(conn, %{"id" => channel_id}) do
    members = Channels.list_channel_members(channel_id)

    conn
    |> put_status(:ok)
    |> json(%{members: Enum.map(members, &format_member/1)})
  end

  @doc """
  POST /api/v1/channels/:id/members
  Add a member to the channel (owner only).
  Body: {userId, role: "admin" | "moderator"}
  """
  def add_member(conn, %{"id" => channel_id} = params) do
    current_user_id = FirebaseAuth.current_user_id(conn)

    if Channels.is_channel_owner?(channel_id, current_user_id) do
      attrs = %{
        "channel_id" => channel_id,
        "user_id" => params["userId"] || params["user_id"],
        "role" => params["role"],
        "added_by" => current_user_id
      }

      case Channels.add_channel_member(attrs) do
        {:ok, member} ->
          conn
          |> put_status(:created)
          |> json(%{member: format_member(member)})

        {:error, :max_members_reached} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Maximum 8 members allowed per channel"})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to add member", errors: format_errors(changeset)})
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Only channel owner can add members"})
    end
  end

  @doc """
  DELETE /api/v1/channels/:id/members/:user_id
  Remove a member from the channel (owner only).
  """
  def remove_member(conn, %{"id" => channel_id, "user_id" => user_id}) do
    current_user_id = FirebaseAuth.current_user_id(conn)

    if Channels.is_channel_owner?(channel_id, current_user_id) do
      case Channels.get_channel_member(channel_id, user_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Member not found"})

        member ->
          case Channels.remove_channel_member(member) do
            {:ok, _} ->
              conn
              |> put_status(:ok)
              |> json(%{message: "Member removed successfully"})

            {:error, _} ->
              conn
              |> put_status(:internal_server_error)
              |> json(%{error: "Failed to remove member"})
          end
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Only channel owner can remove members"})
    end
  end

  ## PRIVATE HELPERS

  defp format_channel(channel) do
    %{
      id: channel.id,
      name: channel.name,
      description: channel.description,
      ownerId: channel.owner_id,
      owner_id: channel.owner_id,
      type: channel.type,
      subscriptionPriceCoins: channel.subscription_price_coins,
      subscription_price_coins: channel.subscription_price_coins,
      isVerified: channel.is_verified,
      is_verified: channel.is_verified,
      subscriberCount: channel.subscriber_count,
      subscriber_count: channel.subscriber_count,
      postCount: channel.post_count,
      post_count: channel.post_count,
      avatarUrl: channel.avatar_url,
      avatar_url: channel.avatar_url,
      bannerUrl: channel.banner_url,
      banner_url: channel.banner_url,
      createdAt: channel.inserted_at,
      created_at: channel.inserted_at,
      updatedAt: channel.updated_at,
      updated_at: channel.updated_at
    }
  end

  defp format_subscription(subscription) do
    %{
      id: subscription.id,
      channelId: subscription.channel_id,
      channel_id: subscription.channel_id,
      userId: subscription.user_id,
      user_id: subscription.user_id,
      unreadCount: subscription.unread_count,
      unread_count: subscription.unread_count,
      lastReadAt: subscription.last_read_at,
      last_read_at: subscription.last_read_at,
      notificationsEnabled: subscription.notifications_enabled,
      notifications_enabled: subscription.notifications_enabled,
      createdAt: subscription.inserted_at,
      created_at: subscription.inserted_at
    }
  end

  defp format_member(member) do
    %{
      id: member.id,
      channelId: member.channel_id,
      channel_id: member.channel_id,
      userId: member.user_id,
      user_id: member.user_id,
      role: member.role,
      addedBy: member.added_by,
      added_by: member.added_by,
      createdAt: member.inserted_at,
      created_at: member.inserted_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
