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
          formatted = format_chat(chat, user_id)
          conn
          |> put_status(:ok)
          |> json(formatted)

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

  @doc """
  POST /api/v1/chats/:id/mark-read
  Mark all messages in a chat as read for the current user.
  """
  def mark_read(conn, %{"id" => chat_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    # Verify user is participant
    unless Chats.participant?(chat_id, user_id) do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Not authorized to access this chat"})
    else
      case Chats.mark_chat_messages_read(chat_id, user_id) do
        {:ok, _chat} ->
          conn
          |> put_status(:ok)
          |> json(%{success: true, message: "Chat marked as read"})

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Failed to mark chat as read", details: reason})
      end
    end
  end

  @doc """
  POST /api/v1/chats/:id/messages
  Send a message in a chat.
  """
  def send_message(conn, %{"id" => chat_id} = params) do
    user_id = FirebaseAuth.current_user_id(conn)

    # Verify user is participant
    unless Chats.participant?(chat_id, user_id) do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Not authorized to send messages in this chat"})
    else
      # Extract media info
      media_url = params["media_url"] || params["mediaUrl"]
      media_type = params["media_type"] || params["mediaType"]

      # Check if this is a video reaction - look in mediaMetadata
      media_metadata = params["mediaMetadata"] || params["media_metadata"] || %{}
      is_video_reaction = media_metadata["isVideoReaction"] || media_metadata["is_video_reaction"] || false

      # If video reaction is present, automatically set media_type to "video"
      final_media_type = if is_video_reaction && media_url && is_nil(media_type), do: "video", else: media_type

      attrs = %{
        chat_id: chat_id,
        sender_id: user_id,
        message_text: params["message_text"] || params["messageText"] || params["content"],
        media_url: media_url,
        media_type: final_media_type
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)  # Remove nil values

      case Chats.send_message(attrs) do
        {:ok, message} ->
          conn
          |> put_status(:created)
          |> json(format_message(message))

        {:error, changeset} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Failed to send message", details: format_errors(changeset)})
      end
    end
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
      message_id: message.id,
      chat_id: message.chat_id,
      sender_id: message.sender_id,
      message_text: message.message_text,
      media_url: message.media_url,
      media_type: message.media_type,
      is_delivered: message.is_delivered,
      delivered_at: message.delivered_at,
      is_read: message.is_read,
      read_at: message.read_at,
      is_deleted: message.is_deleted,
      created_at: message.inserted_at,
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
