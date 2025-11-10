defmodule WemachatCore.Contexts.Chats do
  @moduledoc """
  The Chats context.
  Handles all business logic for 1-on-1 chat conversations and messages.
  """

  import Ecto.Query, warn: false
  alias WemachatDatabase.Repo
  alias WemachatDatabase.Schemas.{Chat, Message}

  ## CHATS

  @doc """
  Get or create a chat between two users.
  Users are automatically ordered canonically.
  """
  def get_or_create_chat(user1_id, user2_id) do
    # Order users canonically
    {ordered_user1, ordered_user2} =
      if user1_id < user2_id, do: {user1_id, user2_id}, else: {user2_id, user1_id}

    case Repo.get_by(Chat, user1_id: ordered_user1, user2_id: ordered_user2) do
      nil ->
        attrs = %{user1_id: ordered_user1, user2_id: ordered_user2}

        %Chat{}
        |> Chat.create_changeset(attrs)
        |> Repo.insert()

      chat ->
        {:ok, chat}
    end
  end

  @doc """
  Get a single chat by ID.
  """
  def get_chat(id), do: Repo.get(Chat, id)

  @doc """
  Get a single chat by ID, raises if not found.
  """
  def get_chat!(id), do: Repo.get!(Chat, id)

  @doc """
  List all chats for a user (ordered by last message).
  """
  def list_user_chats(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    Chat
    |> where([c], (c.user1_id == ^user_id or c.user2_id == ^user_id) and c.is_active == true)
    |> order_by([c], desc: c.last_message_at, desc: c.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Update chat metadata (last message, timestamps).
  """
  def update_chat(%Chat{} = chat, attrs) do
    chat
    |> Chat.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft delete a chat.
  """
  def deactivate_chat(%Chat{} = chat) do
    chat
    |> Chat.update_changeset(%{is_active: false})
    |> Repo.update()
  end

  ## MESSAGES

  @doc """
  Send a message in a chat.
  Automatically updates chat's last message and unread count.
  """
  def send_message(attrs) do
    Repo.transaction(fn ->
      # Create message
      message =
        %Message{}
        |> Message.create_changeset(attrs)
        |> Repo.insert!()

      # Get chat
      chat = get_chat!(message.chat_id)

      # Determine which user sent the message and increment other user's unread
      {user1_unread, user2_unread} =
        cond do
          message.sender_id == chat.user1_id ->
            {chat.user1_unread_count, chat.user2_unread_count + 1}

          message.sender_id == chat.user2_id ->
            {chat.user1_unread_count + 1, chat.user2_unread_count}

          true ->
            {chat.user1_unread_count, chat.user2_unread_count}
        end

      # Update chat with last message info
      chat
      |> Chat.update_changeset(%{
        last_message_text: message.message_text || "[Media]",
        last_message_at: message.inserted_at,
        user1_unread_count: user1_unread,
        user2_unread_count: user2_unread
      })
      |> Repo.update!()

      message
    end)
    |> case do
      {:ok, message} -> {:ok, message}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get a single message by ID.
  """
  def get_message(id), do: Repo.get(Message, id)

  @doc """
  Get messages for a chat (paginated, newest first).
  """
  def list_chat_messages(chat_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)

    Message
    |> where([m], m.chat_id == ^chat_id and m.is_deleted == false)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Mark a message as delivered.
  """
  def mark_message_delivered(%Message{} = message) do
    message
    |> Message.mark_delivered_changeset()
    |> Repo.update()
  end

  @doc """
  Mark a message as read.
  """
  def mark_message_read(%Message{} = message) do
    message
    |> Message.mark_read_changeset()
    |> Repo.update()
  end

  @doc """
  Mark all messages in a chat as read for a specific user.
  Resets the unread count for that user.
  """
  def mark_chat_messages_read(chat_id, user_id) do
    Repo.transaction(fn ->
      # Get chat
      chat = get_chat!(chat_id)

      # Verify user is participant
      unless Chat.participant?(chat, user_id) do
        Repo.rollback(:not_participant)
      end

      # Mark all unread messages from the other user as read
      other_user_id = Chat.other_user_id(chat, user_id)

      Message
      |> where([m], m.chat_id == ^chat_id and m.sender_id == ^other_user_id and m.is_read == false)
      |> Repo.update_all(set: [is_read: true, read_at: DateTime.utc_now()])

      # Reset unread count for this user
      new_attrs =
        if chat.user1_id == user_id do
          %{user1_unread_count: 0}
        else
          %{user2_unread_count: 0}
        end

      chat
      |> Chat.update_changeset(new_attrs)
      |> Repo.update!()
    end)
    |> case do
      {:ok, chat} -> {:ok, chat}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Update a message (edit).
  """
  def update_message(%Message{} = message, attrs) do
    message
    |> Message.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft delete a message.
  """
  def delete_message(%Message{} = message) do
    message
    |> Message.delete_changeset()
    |> Repo.update()
  end

  @doc """
  Get unread message count for a user across all chats.
  """
  def get_total_unread_count(user_id) do
    Chat
    |> where([c], (c.user1_id == ^user_id or c.user2_id == ^user_id) and c.is_active == true)
    |> Repo.all()
    |> Enum.reduce(0, fn chat, acc ->
      acc + Chat.unread_count_for_user(chat, user_id)
    end)
  end

  @doc """
  Check if user is participant in a chat.
  """
  def participant?(chat_id, user_id) do
    case get_chat(chat_id) do
      nil -> false
      chat -> Chat.participant?(chat, user_id)
    end
  end
end
