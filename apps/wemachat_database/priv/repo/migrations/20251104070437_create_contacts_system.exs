defmodule WemachatDatabase.Repo.Migrations.CreateContactsSystem do
  use Ecto.Migration

  def change do
    # Add privacy settings to users table
    alter table(:users) do
      add :who_can_message, :string, default: "everyone", null: false
      # Options: "everyone", "contacts", "nobody"
      add :who_can_call, :string, default: "everyone", null: false
      # Options: "everyone", "contacts", "nobody"
      add :show_online_status, :boolean, default: true, null: false
    end

    # Create contacts table
    create table(:contacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :string, on_delete: :delete_all), null: false
      add :contact_user_id, references(:users, type: :string, on_delete: :delete_all), null: false
      add :display_name, :string
      # Custom name for this contact (optional)
      add :is_favorite, :boolean, default: false, null: false
      add :notes, :text
      # Private notes about this contact

      timestamps(type: :utc_datetime)
    end

    # Create blocked_users table
    create table(:blocked_users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :blocker_id, references(:users, type: :string, on_delete: :delete_all), null: false
      # User who blocked
      add :blocked_id, references(:users, type: :string, on_delete: :delete_all), null: false
      # User who was blocked
      add :reason, :string
      # Optional reason for blocking

      timestamps(type: :utc_datetime)
    end

    # Indexes for contacts
    create unique_index(:contacts, [:user_id, :contact_user_id])
    create index(:contacts, [:user_id])
    create index(:contacts, [:contact_user_id])
    create index(:contacts, [:user_id, :is_favorite])

    # Indexes for blocked_users
    create unique_index(:blocked_users, [:blocker_id, :blocked_id])
    create index(:blocked_users, [:blocker_id])
    create index(:blocked_users, [:blocked_id])

    # Indexes for privacy settings on users
    create index(:users, [:who_can_message])
    create index(:users, [:who_can_call])
  end
end
