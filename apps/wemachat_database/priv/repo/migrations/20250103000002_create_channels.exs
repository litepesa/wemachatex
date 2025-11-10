defmodule WemachatDatabase.Repo.Migrations.CreateChannels do
  use Ecto.Migration

  # ========================================
  # ⚠️ DEPRECATED MIGRATION
  # ========================================
  # This migration creates the OLD channel system that has been removed.
  # It is superseded by migration: 20251106000001_convert_videos_to_user_based.exs
  #
  # The new migration drops all tables created here and replaces them with
  # a user-based video system.
  #
  # DO NOT RUN THIS MIGRATION on new databases!
  # It is kept for historical reference only.
  # ========================================

  def change do
    # ========================================
    # CHANNELS TABLE
    # One channel per user (creator profile)
    # ========================================
    create table(:channels, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Owner (foreign key to users)
      add :user_id, references(:users, type: :string, on_delete: :delete_all), null: false

      # Channel Info
      add :channel_name, :string, null: false
      add :channel_avatar, :text, default: ""
      add :bio, :text, default: ""
      add :category, :string, default: "General"
      add :tags, {:array, :string}, default: []

      # Contact Info (optional)
      add :website_url, :string
      add :contact_email, :string

      # Status Flags
      add :is_verified, :boolean, default: false
      add :is_active, :boolean, default: true
      add :is_featured, :boolean, default: false

      # Metrics
      add :followers_count, :integer, default: 0
      add :videos_count, :integer, default: 0
      add :total_views, :integer, default: 0
      add :total_likes, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    # Indexes
    create unique_index(:channels, [:user_id]) # One channel per user
    create index(:channels, [:channel_name])
    create index(:channels, [:category])
    create index(:channels, [:is_verified])
    create index(:channels, [:is_featured])
    create index(:channels, [:followers_count])
    create index(:channels, [:tags], using: :gin)

    # ========================================
    # VIDEOS TABLE
    # Videos belong to channels with 72h expiry
    # ========================================
    create table(:videos, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Channel reference
      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false

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

    # Indexes
    create index(:videos, [:channel_id])
    create index(:videos, [:is_active])
    create index(:videos, [:is_featured])
    create index(:videos, [:expires_at]) # Critical for expiry queries
    create index(:videos, [:inserted_at])
    create index(:videos, [:views])
    create index(:videos, [:likes])
    create index(:videos, [:tags], using: :gin)

    # Composite index for feed queries (active + not expired)
    create index(:videos, [:is_active, :expires_at, :inserted_at])

    # Full-text search on caption
    execute """
    CREATE INDEX videos_caption_search_idx ON videos
    USING gin(to_tsvector('english', coalesce(caption, '')))
    """, "DROP INDEX videos_caption_search_idx"

    # ========================================
    # CHANNEL FOLLOWS TABLE
    # Users follow channels
    # ========================================
    create table(:channel_follows, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :follower_user_id, :string, null: false # Firebase UID
      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # Indexes
    create unique_index(:channel_follows, [:follower_user_id, :channel_id])
    create index(:channel_follows, [:follower_user_id])
    create index(:channel_follows, [:channel_id])

    # ========================================
    # VIDEO LIKES TABLE
    # Users like videos
    # ========================================
    create table(:video_likes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id, :string, null: false # Firebase UID
      add :video_id, references(:videos, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # Indexes
    create unique_index(:video_likes, [:user_id, :video_id])
    create index(:video_likes, [:user_id])
    create index(:video_likes, [:video_id])

    # ========================================
    # VIDEO COMMENTS TABLE
    # Users comment on videos
    # ========================================
    create table(:video_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :video_id, references(:videos, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, :string, null: false # Firebase UID
      add :comment_text, :text, null: false

      # Optional media attachment
      add :image_url, :text

      timestamps(type: :utc_datetime)
    end

    # Indexes
    create index(:video_comments, [:video_id])
    create index(:video_comments, [:user_id])
    create index(:video_comments, [:inserted_at])
  end
end
