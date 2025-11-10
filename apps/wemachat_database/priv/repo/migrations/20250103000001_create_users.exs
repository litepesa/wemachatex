defmodule WemachatDatabase.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      # Primary Key (Firebase UID)
      add :id, :string, primary_key: true

      # Core Profile Fields
      add :phone_number, :string, null: false
      add :whatsapp_number, :string
      add :name, :string, null: false
      add :bio, :text, default: ""
      add :profile_image, :text, default: ""
      add :cover_image, :text, default: ""

      # Engagement Metrics
      add :followers_count, :integer, default: 0
      add :following_count, :integer, default: 0
      add :videos_count, :integer, default: 0
      add :likes_count, :integer, default: 0

      # Status Flags
      add :is_verified, :boolean, default: false
      add :is_active, :boolean, default: true
      add :is_featured, :boolean, default: false
      add :is_live, :boolean, default: false

      # Permission/Role Fields (Staff)
      add :is_admin, :boolean, default: false
      add :is_moderator, :boolean, default: false

      # Restriction Fields (Bans)
      add :can_comment, :boolean, default: true
      add :can_post, :boolean, default: true

      # Demographics (Kenya-specific)
      add :gender, :string
      add :location, :string
      add :language, :string

      # Arrays (PostgreSQL arrays)
      add :tags, {:array, :string}, default: []
      add :follower_uids, {:array, :string}, default: []
      add :following_uids, {:array, :string}, default: []
      add :liked_videos, {:array, :string}, default: []

      # Preferences (JSONB)
      add :preferences, :map, default: %{
        "autoPlay" => true,
        "receiveNotifications" => true,
        "darkMode" => false
      }

      # Timestamps
      add :last_seen, :utc_datetime, default: fragment("NOW()")
      add :last_post_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Indexes for performance
    create unique_index(:users, [:phone_number])
    create index(:users, [:name])
    create index(:users, [:is_verified])
    create index(:users, [:is_active])
    create index(:users, [:is_live])
    create index(:users, [:gender])
    create index(:users, [:location])
    create index(:users, [:language])
    create index(:users, [:last_seen])
    create index(:users, [:inserted_at])

    # GIN index for array fields (enables fast array queries)
    create index(:users, [:follower_uids], using: :gin)
    create index(:users, [:following_uids], using: :gin)
    create index(:users, [:tags], using: :gin)

    # Full-text search index on name and bio (for user search)
    execute """
    CREATE INDEX users_name_bio_search_idx ON users
    USING gin(to_tsvector('english', coalesce(name, '') || ' ' || coalesce(bio, '')))
    """, "DROP INDEX users_name_bio_search_idx"
  end
end
