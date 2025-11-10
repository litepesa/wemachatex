defmodule WemachatApiWeb.ChatChannel do
  use WemachatApiWeb, :channel

  alias WemachatCore.Contexts.Chats

  @impl true
  def join("chat:" <> chat_id, _payload, socket) do
    user_id = socket.assigns.user_id

    # Verify user is participant in this chat
    if Chats.participant?(chat_id, user_id) do
      {:ok, %{status: "joined", chat_id: chat_id}, assign(socket, :chat_id, chat_id)}
    else
      {:error, %{reason: "not_authorized"}}
    end
  end

  @impl true
  def handle_in("new_message", payload, socket) do
    user_id = socket.assigns.user_id
    chat_id = socket.assigns.chat_id

    attrs = %{
      chat_id: chat_id,
      sender_id: user_id,
      message_text: payload["message_text"],
      media_url: payload["media_url"],
      media_type: payload["media_type"]
    }

    case Chats.send_message(attrs) do
      {:ok, message} ->
        # Broadcast to all participants in the chat
        broadcast(socket, "message_received", format_message(message))
        {:reply, {:ok, format_message(message)}, socket}

      {:error, changeset} ->
        {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
    end
  end

  @impl true
  def handle_in("mark_delivered", %{"message_id" => message_id}, socket) do
    case Chats.get_message(message_id) do
      nil ->
        {:reply, {:error, %{reason: "message_not_found"}}, socket}

      message ->
        case Chats.mark_message_delivered(message) do
          {:ok, updated} ->
            # Broadcast delivery status to sender
            broadcast(socket, "message_delivered", %{
              message_id: updated.id,
              delivered_at: updated.delivered_at
            })

            {:reply, :ok, socket}

          {:error, _} ->
            {:reply, {:error, %{reason: "failed_to_mark_delivered"}}, socket}
        end
    end
  end

  @impl true
  def handle_in("mark_read", %{"message_id" => message_id}, socket) do
    case Chats.get_message(message_id) do
      nil ->
        {:reply, {:error, %{reason: "message_not_found"}}, socket}

      message ->
        case Chats.mark_message_read(message) do
          {:ok, updated} ->
            # Broadcast read status to sender
            broadcast(socket, "message_read", %{
              message_id: updated.id,
              read_at: updated.read_at
            })

            {:reply, :ok, socket}

          {:error, _} ->
            {:reply, {:error, %{reason: "failed_to_mark_read"}}, socket}
        end
    end
  end

  @impl true
  def handle_in("mark_all_read", _payload, socket) do
    user_id = socket.assigns.user_id
    chat_id = socket.assigns.chat_id

    case Chats.mark_chat_messages_read(chat_id, user_id) do
      {:ok, _chat} ->
        # Broadcast to other user that messages were read
        broadcast(socket, "all_messages_read", %{
          user_id: user_id,
          chat_id: chat_id,
          read_at: DateTime.utc_now()
        })

        {:reply, :ok, socket}

      {:error, _} ->
        {:reply, {:error, %{reason: "failed_to_mark_read"}}, socket}
    end
  end

  @impl true
  def handle_in("typing_start", _payload, socket) do
    user_id = socket.assigns.user_id

    # Broadcast typing indicator to other participant
    broadcast_from(socket, "user_typing", %{
      user_id: user_id,
      typing: true
    })

    {:noreply, socket}
  end

  @impl true
  def handle_in("typing_stop", _payload, socket) do
    user_id = socket.assigns.user_id

    # Broadcast stop typing to other participant
    broadcast_from(socket, "user_typing", %{
      user_id: user_id,
      typing: false
    })

    {:noreply, socket}
  end

  ## Private Functions

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
end
