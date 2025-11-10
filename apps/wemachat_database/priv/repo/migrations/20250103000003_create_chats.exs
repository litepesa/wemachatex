defmodule WemachatDatabase.Repo.Migrations.CreateChats do
  use Ecto.Migration

  def change do
    # Chats table - 1-on-1 conversation threads
    create table(:chats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user1_id, references(:users, type: :string, on_delete: :delete_all), null: false
      add :user2_id, references(:users, type: :string, on_delete: :delete_all), null: false

      # Last message info (for chat list display)
      add :last_message_text, :text
      add :last_message_at, :utc_datetime_usec

      # Unread counts per user
      add :user1_unread_count, :integer, default: 0, null: false
      add :user2_unread_count, :integer, default: 0, null: false

      # Soft delete
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Ensure users are ordered canonically (user1_id < user2_id)
    # This prevents duplicate chats (A->B and B->A)
    create constraint(:chats, :user_ordering,
             check: "user1_id < user2_id"
           )

    # Unique constraint - one chat per user pair
    create unique_index(:chats, [:user1_id, :user2_id])

    # Indexes for querying chats by user
    create index(:chats, [:user1_id, :last_message_at])
    create index(:chats, [:user2_id, :last_message_at])
    create index(:chats, [:is_active])

    # Messages table - individual messages in a chat
    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :chat_id, references(:chats, type: :binary_id, on_delete: :delete_all), null: false
      add :sender_id, references(:users, type: :string, on_delete: :delete_all), null: false

      # Message content
      add :message_text, :text
      add :media_url, :string
      add :media_type, :string # "image", "video", "audio", "file"

      # Delivery status
      add :is_delivered, :boolean, default: false, null: false
      add :delivered_at, :utc_datetime_usec

      # Read status
      add :is_read, :boolean, default: false, null: false
      add :read_at, :utc_datetime_usec

      # Soft delete
      add :is_deleted, :boolean, default: false, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for message queries
    create index(:messages, [:chat_id, :inserted_at])
    create index(:messages, [:sender_id])
    create index(:messages, [:chat_id, :is_read])
    create index(:messages, [:chat_id, :is_delivered])

    # Check constraint - message must have text or media
    create constraint(:messages, :message_content,
             check: "message_text IS NOT NULL OR media_url IS NOT NULL"
           )
  end
end
