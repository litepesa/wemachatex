defmodule WemachatDatabase.Schemas.Chat do
  @moduledoc """
  Schema for 1-on-1 chat conversations.
  Users are stored in canonical order (user1_id < user2_id) to prevent duplicates.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.Message

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           except: [:__meta__, :messages]}

  schema "chats" do
    field :user1_id, :string
    field :user2_id, :string
    field :last_message_text, :string
    field :last_message_at, :utc_datetime_usec
    field :user1_unread_count, :integer, default: 0
    field :user2_unread_count, :integer, default: 0
    field :is_active, :boolean, default: true

    has_many :messages, Message, foreign_key: :chat_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a chat.
  Automatically orders users canonically (user1_id < user2_id).
  """
  def create_changeset(chat, attrs) do
    chat
    |> cast(attrs, [:user1_id, :user2_id])
    |> validate_required([:user1_id, :user2_id])
    |> validate_different_users()
    |> order_users_canonically()
    |> check_constraint(:user1_id,
      name: :user_ordering,
      message: "User ordering constraint violated"
    )
    |> unique_constraint([:user1_id, :user2_id],
      name: :chats_user1_id_user2_id_index,
      message: "Chat already exists between these users"
    )
  end

  @doc """
  Changeset for updating chat metadata (last message, unread counts).
  """
  def update_changeset(chat, attrs) do
    chat
    |> cast(attrs, [
      :last_message_text,
      :last_message_at,
      :user1_unread_count,
      :user2_unread_count,
      :is_active
    ])
    |> validate_number(:user1_unread_count, greater_than_or_equal_to: 0)
    |> validate_number(:user2_unread_count, greater_than_or_equal_to: 0)
  end

  @doc """
  Get the other user's ID in the chat (given one user's ID).
  """
  def other_user_id(%__MODULE__{user1_id: user1_id, user2_id: user2_id}, current_user_id) do
    cond do
      user1_id == current_user_id -> user2_id
      user2_id == current_user_id -> user1_id
      true -> nil
    end
  end

  @doc """
  Get unread count for a specific user.
  """
  def unread_count_for_user(%__MODULE__{} = chat, user_id) do
    cond do
      chat.user1_id == user_id -> chat.user1_unread_count
      chat.user2_id == user_id -> chat.user2_unread_count
      true -> 0
    end
  end

  @doc """
  Check if user is participant in this chat.
  """
  def participant?(%__MODULE__{user1_id: user1_id, user2_id: user2_id}, user_id) do
    user1_id == user_id or user2_id == user_id
  end

  ## Private Functions

  defp validate_different_users(changeset) do
    user1_id = get_field(changeset, :user1_id)
    user2_id = get_field(changeset, :user2_id)

    if user1_id && user2_id && user1_id == user2_id do
      add_error(changeset, :user2_id, "cannot chat with yourself")
    else
      changeset
    end
  end

  defp order_users_canonically(changeset) do
    user1_id = get_field(changeset, :user1_id)
    user2_id = get_field(changeset, :user2_id)

    # Use case-insensitive comparison to match PostgreSQL's collation behavior
    if user1_id && user2_id && String.downcase(user1_id) > String.downcase(user2_id) do
      changeset
      |> put_change(:user1_id, user2_id)
      |> put_change(:user2_id, user1_id)
    else
      changeset
    end
  end
end
