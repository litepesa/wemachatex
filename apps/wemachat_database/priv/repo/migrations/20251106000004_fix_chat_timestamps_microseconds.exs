defmodule WemachatDatabase.Repo.Migrations.FixChatTimestampsMicroseconds do
  use Ecto.Migration

  def change do
    # Alter chats table timestamp columns to use timestamp(6) for microsecond precision
    alter table(:chats) do
      modify :last_message_at, :utc_datetime_usec
      modify :inserted_at, :utc_datetime_usec
      modify :updated_at, :utc_datetime_usec
    end

    # Alter messages table timestamp columns to use timestamp(6) for microsecond precision
    alter table(:messages) do
      modify :delivered_at, :utc_datetime_usec
      modify :read_at, :utc_datetime_usec
      modify :inserted_at, :utc_datetime_usec
      modify :updated_at, :utc_datetime_usec
    end
  end
end
