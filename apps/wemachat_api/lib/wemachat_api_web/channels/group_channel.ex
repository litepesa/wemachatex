defmodule WemachatApiWeb.GroupChannel do
  @moduledoc """
  Channel for real-time group messaging.
  Handles message broadcasting, typing indicators, and member events.
  """
  use WemachatApiWeb, :channel

  alias WemachatCore.Contexts.Groups
  alias WemachatDatabase.Repo

  @doc """
  Join a group channel.
  Client connects to: "group:{group_id}"
  """
  def join("group:" <> group_id, _params, socket) do
    user_id = socket.assigns.user_id

    # Verify user is a member of this group
    if Groups.member?(group_id, user_id) do
      # Track this user in the group
      send(self(), :after_join)

      {:ok, %{status: "joined", group_id: group_id}, assign(socket, :group_id, group_id)}
    else
      {:error, %{reason: "not_a_member"}}
    end
  end

  @doc """
  Handle after join - notify other members
  """
  def handle_info(:after_join, socket) do
    # Broadcast user joined
    broadcast!(socket, "member_joined", %{
      user_id: socket.assigns.user_id,
      timestamp: DateTime.utc_now()
    })

    {:noreply, socket}
  end

  @doc """
  Handle incoming messages from client
  """
  def handle_in("new_message", %{"message_text" => _message_text} = params, socket) do
    user_id = socket.assigns.user_id
    group_id = socket.assigns.group_id

    attrs = %{
      group_id: group_id,
      sender_id: user_id,
      message_text: params["message_text"],
      media_url: params["media_url"],
      media_type: params["media_type"]
    }

    case Groups.send_message(attrs) do
      {:ok, message} ->
        # Broadcast to all group members
        broadcast!(socket, "new_message", %{
          id: message.id,
          group_id: message.group_id,
          sender_id: message.sender_id,
          message_text: message.message_text,
          media_url: message.media_url,
          media_type: message.media_type,
          read_by: message.read_by,
          inserted_at: message.inserted_at
        })

        {:reply, {:ok, %{message: message}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  @doc """
  Handle typing indicator
  """
  def handle_in("typing", _params, socket) do
    broadcast_from!(socket, "user_typing", %{
      user_id: socket.assigns.user_id,
      timestamp: DateTime.utc_now()
    })

    {:noreply, socket}
  end

  @doc """
  Handle stop typing indicator
  """
  def handle_in("stop_typing", _params, socket) do
    broadcast_from!(socket, "user_stopped_typing", %{
      user_id: socket.assigns.user_id,
      timestamp: DateTime.utc_now()
    })

    {:noreply, socket}
  end

  @doc """
  Handle message read receipt
  """
  def handle_in("mark_read", %{"message_id" => message_id}, socket) do
    user_id = socket.assigns.user_id

    case Groups.mark_message_as_read(message_id, user_id) do
      {:ok, message} ->
        # Broadcast read receipt to all members
        broadcast!(socket, "message_read", %{
          message_id: message_id,
          user_id: user_id,
          read_by: message.read_by,
          timestamp: DateTime.utc_now()
        })

        {:reply, {:ok, %{message: "marked_read"}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  @doc """
  Handle delete message
  """
  def handle_in("delete_message", %{"message_id" => message_id}, socket) do
    user_id = socket.assigns.user_id

    case Groups.delete_message(message_id, user_id) do
      {:ok, _message} ->
        # Broadcast deletion to all members
        broadcast!(socket, "message_deleted", %{
          message_id: message_id,
          deleted_by: user_id,
          timestamp: DateTime.utc_now()
        })

        {:reply, {:ok, %{message: "deleted"}}, socket}

      {:error, :unauthorized} ->
        {:reply, {:error, %{reason: "unauthorized"}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  @doc """
  Handle member added event (triggered from REST API)
  """
  def handle_in("member_added", %{"user_ids" => user_ids}, socket) do
    user_id = socket.assigns.user_id
    group_id = socket.assigns.group_id

    # Verify user is admin
    if Groups.admin?(group_id, user_id) do
      broadcast!(socket, "members_added", %{
        user_ids: user_ids,
        added_by: user_id,
        timestamp: DateTime.utc_now()
      })

      {:reply, {:ok, %{message: "broadcasted"}}, socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  @doc """
  Handle member removed event (triggered from REST API)
  """
  def handle_in("member_removed", %{"user_id" => removed_user_id}, socket) do
    user_id = socket.assigns.user_id
    group_id = socket.assigns.group_id

    # Verify user is admin or removing themselves
    if Groups.admin?(group_id, user_id) or user_id == removed_user_id do
      broadcast!(socket, "member_removed", %{
        user_id: removed_user_id,
        removed_by: user_id,
        timestamp: DateTime.utc_now()
      })

      {:reply, {:ok, %{message: "broadcasted"}}, socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  @doc """
  Handle group updated event (triggered from REST API)
  """
  def handle_in("group_updated", %{"updates" => updates}, socket) do
    user_id = socket.assigns.user_id
    group_id = socket.assigns.group_id

    # Verify user is admin
    if Groups.admin?(group_id, user_id) do
      broadcast!(socket, "group_updated", %{
        updates: updates,
        updated_by: user_id,
        timestamp: DateTime.utc_now()
      })

      {:reply, {:ok, %{message: "broadcasted"}}, socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  @doc """
  Terminate - broadcast user left
  """
  def terminate(_reason, socket) do
    broadcast!(socket, "member_left", %{
      user_id: socket.assigns.user_id,
      timestamp: DateTime.utc_now()
    })

    :ok
  end
end
