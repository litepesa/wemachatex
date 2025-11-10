defmodule WemachatDatabase.Repo.Migrations.FixDatetimeMicroseconds do
  use Ecto.Migration

  def up do
    # ========================================
    # FIX: Change :utc_datetime to :utc_datetime_usec
    # to support RFC 3339 timestamps with microseconds
    # ========================================

    # Alter users table timestamps
    alter table(:users) do
      modify :last_seen, :utc_datetime_usec
      modify :last_post_at, :utc_datetime_usec
      modify :inserted_at, :utc_datetime_usec, null: false
      modify :updated_at, :utc_datetime_usec, null: false
    end

    # Alter videos table timestamps
    alter table(:videos) do
      modify :expires_at, :utc_datetime_usec, null: false
      modify :inserted_at, :utc_datetime_usec, null: false
      modify :updated_at, :utc_datetime_usec, null: false
    end

    # Alter video_likes table timestamps
    alter table(:video_likes) do
      modify :inserted_at, :utc_datetime_usec, null: false
    end

    # Alter video_comments table timestamps
    alter table(:video_comments) do
      modify :inserted_at, :utc_datetime_usec, null: false
      modify :updated_at, :utc_datetime_usec, null: false
    end

    # Alter chats table timestamps
    alter table(:chats) do
      modify :last_message_at, :utc_datetime_usec
      modify :inserted_at, :utc_datetime_usec, null: false
      modify :updated_at, :utc_datetime_usec, null: false
    end

    # Alter messages table timestamps
    alter table(:messages) do
      modify :inserted_at, :utc_datetime_usec, null: false
      modify :updated_at, :utc_datetime_usec, null: false
    end

    # Note: follows and contacts tables will be added in future migrations
  end

  def down do
    # No rollback - schema must support microseconds for RFC 3339 compatibility
    raise "Cannot rollback to :utc_datetime - microsecond support is required for RFC 3339 timestamps"
  end
end
