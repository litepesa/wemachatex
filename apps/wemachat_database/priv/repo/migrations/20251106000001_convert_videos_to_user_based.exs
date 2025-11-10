defmodule WemachatDatabase.Repo.Migrations.ConvertVideosToUserBased do
  use Ecto.Migration

  def up do
    # ========================================
    # MIGRATION: Convert videos from channel-based to user-based
    # AND remove old channel functionality
    # ========================================

    # Step 1: Drop old channel-related tables (preparing for new channel feature)
    drop_if_exists table(:video_likes)
    drop_if_exists table(:video_comments)
    drop_if_exists table(:channel_follows)
    drop_if_exists table(:videos)
    drop_if_exists table(:channels)

    # Step 2: Recreate videos table with user_id (fresh start)
    create table(:videos, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # User reference (videos belong to users directly)
      add :user_id, references(:users, type: :string, on_delete: :delete_all), null: false

      # Media URLs
      add :video_url, :text, null: false
      add :thumbnail_url, :text, default: ""

      # Content
      add :caption, :text, default: ""
      add :tags, {:array, :string}, default: []

      # Engagement Metrics
      add :views, :integer, default: 0
      add :likes, :integer, default: 0
      add :comments, :integer, default: 0
      add :shares, :integer, default: 0

      # Status Flags
      add :is_active, :boolean, default: true
      add :is_featured, :boolean, default: false

      # Boost System
      add :is_boosted, :boolean, default: false
      add :boost_tier, :string, default: "none"
      add :super_boost, :boolean, default: false

      # Premium Content
      add :price, :decimal, precision: 10, scale: 2, default: 0.0

      # Multiple Images Support
      add :is_multiple_images, :boolean, default: false
      add :image_urls, {:array, :string}, default: []

      # 72-HOUR EXPIRY
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    # Step 3: Create indexes for videos table
    create index(:videos, [:user_id])
    create index(:videos, [:is_active])
    create index(:videos, [:is_featured])
    create index(:videos, [:expires_at])
    create index(:videos, [:inserted_at])
    create index(:videos, [:views])
    create index(:videos, [:likes])
    create index(:videos, [:tags], using: :gin)
    create index(:videos, [:is_active, :expires_at, :inserted_at])

    # Full-text search on caption
    execute """
    CREATE INDEX videos_caption_search_idx ON videos
    USING gin(to_tsvector('english', coalesce(caption, '')))
    """, "DROP INDEX videos_caption_search_idx"

    # Step 4: Recreate video_likes table
    create table(:video_likes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :video_id, references(:videos, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:video_likes, [:user_id, :video_id])
    create index(:video_likes, [:user_id])
    create index(:video_likes, [:video_id])

    # Step 5: Recreate video_comments table
    create table(:video_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :video_id, references(:videos, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, :string, null: false
      add :comment_text, :text, null: false
      add :image_url, :text

      timestamps(type: :utc_datetime)
    end

    create index(:video_comments, [:video_id])
    create index(:video_comments, [:user_id])
    create index(:video_comments, [:inserted_at])
  end

  def down do
    # ========================================
    # ROLLBACK: Not supported - old channel system removed
    # ========================================
    raise "Cannot rollback - old channel system has been removed"
  end
end
