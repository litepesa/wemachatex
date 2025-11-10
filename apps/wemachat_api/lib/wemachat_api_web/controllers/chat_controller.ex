defmodule WemachatApiWeb.ChatController do
  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.Chats
  alias WemachatApiWeb.Plugs.FirebaseAuth

  # Apply Firebase auth to all routes
  plug FirebaseAuth

  @doc """
  GET /api/v1/chats
  List all chats for the current user.
  """
  def index(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    chats = Chats.list_user_chats(user_id, page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      chats: Enum.map(chats, &format_chat(&1, user_id)),
      page: page,
      per_page: per_page
    })
  end

  @doc """
  GET /api/v1/chats/:id
  Get a specific chat.
  """
  def show(conn, %{"id" => id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Chats.get_chat(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Chat not found"})

      chat ->
        # Verify user is participant
        unless WemachatDatabase.Schemas.Chat.participant?(chat, user_id) do
          conn
          |> put_status(:forbidden)
          |> json(%{error: "Not authorized to access this chat"})
        else
          conn
          |> put_status(:ok)
          |> json(format_chat(chat, user_id))
        end
    end
  end

  @doc """
  POST /api/v1/chats
  Get or create a chat with another user.
  """
  def create(conn, %{"other_user_id" => other_user_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    if user_id == other_user_id do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Cannot create chat with yourself"})
    else
      case Chats.get_or_create_chat(user_id, other_user_id) do
        {:ok, chat} ->
          conn
          |> put_status(:ok)
          |> json(format_chat(chat, user_id))

        {:error, changeset} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Failed to create chat", details: format_errors(changeset)})
      end
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: other_user_id"})
  end

  @doc """
  GET /api/v1/chats/:id/messages
  Get message history for a chat.
  """
  def messages(conn, %{"id" => chat_id} = params) do
    user_id = FirebaseAuth.current_user_id(conn)

    # Verify user is participant
    unless Chats.participant?(chat_id, user_id) do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Not authorized to access this chat"})
    else
      page = parse_int(params["page"], 1)
      per_page = parse_int(params["per_page"], 50)

      messages = Chats.list_chat_messages(chat_id, page: page, per_page: per_page)

      conn
      |> put_status(:ok)
      |> json(%{
        messages: Enum.map(messages, &format_message/1),
        page: page,
        per_page: per_page
      })
    end
  end

  @doc """
  GET /api/v1/chats/unread_count
  Get total unread message count for the current user.
  """
  def unread_count(conn, _params) do
    user_id = FirebaseAuth.current_user_id(conn)
    count = Chats.get_total_unread_count(user_id)

    conn
    |> put_status(:ok)
    |> json(%{unread_count: count})
  end

  ## Private Functions

  defp format_chat(chat, current_user_id) do
    %{
      id: chat.id,
      user1Id: chat.user1_id,
      user1_id: chat.user1_id,
      user2Id: chat.user2_id,
      user2_id: chat.user2_id,
      otherUserId:
        WemachatDatabase.Schemas.Chat.other_user_id(chat, current_user_id),
      other_user_id:
        WemachatDatabase.Schemas.Chat.other_user_id(chat, current_user_id),
      lastMessageText: chat.last_message_text,
      last_message_text: chat.last_message_text,
      lastMessageAt: chat.last_message_at,
      last_message_at: chat.last_message_at,
      unreadCount:
        WemachatDatabase.Schemas.Chat.unread_count_for_user(chat, current_user_id),
      unread_count:
        WemachatDatabase.Schemas.Chat.unread_count_for_user(chat, current_user_id),
      isActive: chat.is_active,
      is_active: chat.is_active,
      createdAt: chat.inserted_at,
      created_at: chat.inserted_at,
      updatedAt: chat.updated_at,
      updated_at: chat.updated_at
    }
  end

  defp format_message(message) do
    %{
      id: message.id,
      chatId: message.chat_id,
      chat_id: message.chat_id,
      senderId: message.sender_id,
      sender_id: message.sender_id,
      messageText: message.message_text,
      message_text: message.message_text,
      mediaUrl: message.media_url,
      media_url: message.media_url,
      mediaType: message.media_type,
      media_type: message.media_type,
      isDelivered: message.is_delivered,
      is_delivered: message.is_delivered,
      deliveredAt: message.delivered_at,
      delivered_at: message.delivered_at,
      isRead: message.is_read,
      is_read: message.is_read,
      readAt: message.read_at,
      read_at: message.read_at,
      isDeleted: message.is_deleted,
      is_deleted: message.is_deleted,
      createdAt: message.inserted_at,
      created_at: message.inserted_at,
      updatedAt: message.updated_at,
      updated_at: message.updated_at
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
end
