defmodule WemachatDatabase.Repo.Migrations.CreateBroadcastChannelsSystem do
  @moduledoc """
  Creates the broadcast channels system - a WhatsApp/Telegram Channels equivalent.

  Features:
  - Public, private, and premium channel types
  - Multi-threaded comments with unlimited nesting (Twitter/Reddit style)
  - Up to 8 admins/moderators per channel
  - Premium posts with coin-based unlocking (80/20 revenue split)
  - 5 content types: text, image, video, audio, document
  - Silent notifications by default with unread tracking
  """
  use Ecto.Migration

  def change do
    # ========================================
    # CHANNELS TABLE
    # Broadcast hubs for content distribution
    # ========================================
    create table(:channels, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Basic Info
      add :name, :string, null: false
      add :description, :text, null: false
      add :owner_id, :string, null: false # Firebase UID
      add :avatar_url, :text

      # Channel Type (public, private, premium)
      add :type, :string, null: false, default: "public"
      add :subscription_price_coins, :integer

      # Status & Verification
      add :is_verified, :boolean, default: false

      # Metrics (auto-updated via triggers)
      add :subscriber_count, :integer, default: 0
      add :post_count, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    # Indexes
    create unique_index(:channels, [:name])
    create index(:channels, [:owner_id])
    create index(:channels, [:type])
    create index(:channels, [:is_verified])
    create index(:channels, [:subscriber_count])

    # ========================================
    # CHANNEL POSTS TABLE
    # Content published in channels
    # ========================================
    create table(:channel_posts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :author_id, :string, null: false # Firebase UID

      # Content Type (text, image, video, audio, document)
      add :content_type, :string, null: false, default: "text"
      add :text, :text
      add :media_url, :text
      add :media_urls, {:array, :string} # For multiple images
      add :media_thumbnail_url, :text
      add :media_size_bytes, :bigint
      add :media_duration_seconds, :integer

      # Premium Content
      add :is_premium, :boolean, default: false
      add :price_coins, :integer
      add :preview_duration_seconds, :integer

      # Engagement Metrics (auto-updated via triggers)
      add :likes, :integer, default: 0
      add :comments_count, :integer, default: 0
      add :views, :integer, default: 0
      add :unlocks, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    # Indexes
    create index(:channel_posts, [:channel_id])
    create index(:channel_posts, [:author_id])
    create index(:channel_posts, [:content_type])
    create index(:channel_posts, [:is_premium])
    create index(:channel_posts, [:inserted_at])
    # Composite index for feed queries
    create index(:channel_posts, [:channel_id, :inserted_at])

    # ========================================
    # CHANNEL COMMENTS TABLE
    # Multi-threaded comments with unlimited nesting
    # ========================================
    create table(:channel_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :post_id, references(:channel_posts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :author_id, :string, null: false # Firebase UID

      # Threading support
      add :parent_id, references(:channel_comments, type: :binary_id, on_delete: :delete_all)
      add :path, {:array, :binary_id}, default: []
      add :depth, :integer, default: 0

      # Content
      add :text, :text, null: false
      add :media_url, :text
      add :media_type, :string # image or video

      # Engagement
      add :likes, :integer, default: 0
      add :replies_count, :integer, default: 0
      add :is_pinned, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    # Indexes
    create index(:channel_comments, [:post_id])
    create index(:channel_comments, [:author_id])
    create index(:channel_comments, [:parent_id])
    create index(:channel_comments, [:path], using: :gin)
    create index(:channel_comments, [:is_pinned])
    create index(:channel_comments, [:inserted_at])
    # Composite index for threaded comment queries
    create index(:channel_comments, [:post_id, :parent_id, :inserted_at])

    # ========================================
    # CHANNEL MEMBERS TABLE
    # Admins and moderators (max 8 per channel)
    # ========================================
    create table(:channel_members, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, :string, null: false # Firebase UID
      add :role, :string, null: false # admin or moderator
      add :added_by, :string, null: false # Firebase UID of who added them

      timestamps(type: :utc_datetime)
    end

    # Indexes
    create unique_index(:channel_members, [:channel_id, :user_id])
    create index(:channel_members, [:channel_id])
    create index(:channel_members, [:user_id])
    create index(:channel_members, [:role])

    # ========================================
    # CHANNEL SUBSCRIPTIONS TABLE
    # User subscriptions with unread tracking
    # ========================================
    create table(:channel_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, :string, null: false # Firebase UID

      # Unread tracking
      add :unread_count, :integer, default: 0
      add :last_read_at, :utc_datetime

      # Notifications (silent by default)
      add :notifications_enabled, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    # Indexes
    create unique_index(:channel_subscriptions, [:channel_id, :user_id])
    create index(:channel_subscriptions, [:channel_id])
    create index(:channel_subscriptions, [:user_id])
    create index(:channel_subscriptions, [:unread_count])

    # ========================================
    # POST UNLOCKS TABLE
    # Tracks premium post unlocks (80/20 revenue split)
    # ========================================
    create table(:post_unlocks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :post_id, references(:channel_posts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, :string, null: false # Firebase UID

      # Payment tracking
      add :coins_paid, :integer, null: false
      add :creator_revenue, :integer, null: false # 80%
      add :platform_revenue, :integer, null: false # 20%

      timestamps(type: :utc_datetime)
    end

    # Indexes
    create unique_index(:post_unlocks, [:post_id, :user_id])
    create index(:post_unlocks, [:post_id])
    create index(:post_unlocks, [:user_id])
    create index(:post_unlocks, [:inserted_at])

    # ========================================
    # TRIGGERS FOR AUTO-UPDATING COUNTS
    # ========================================

    # Trigger to update channel subscriber_count
    execute """
    CREATE OR REPLACE FUNCTION update_channel_subscriber_count()
    RETURNS TRIGGER AS $$
    BEGIN
      IF TG_OP = 'INSERT' THEN
        UPDATE channels SET subscriber_count = subscriber_count + 1 WHERE id = NEW.channel_id;
      ELSIF TG_OP = 'DELETE' THEN
        UPDATE channels SET subscriber_count = GREATEST(0, subscriber_count - 1) WHERE id = OLD.channel_id;
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """,
    "DROP FUNCTION IF EXISTS update_channel_subscriber_count() CASCADE"

    execute """
    CREATE TRIGGER trigger_update_channel_subscriber_count
    AFTER INSERT OR DELETE ON channel_subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_channel_subscriber_count();
    """,
    "DROP TRIGGER IF EXISTS trigger_update_channel_subscriber_count ON channel_subscriptions"

    # Trigger to update channel post_count
    execute """
    CREATE OR REPLACE FUNCTION update_channel_post_count()
    RETURNS TRIGGER AS $$
    BEGIN
      IF TG_OP = 'INSERT' THEN
        UPDATE channels SET post_count = post_count + 1 WHERE id = NEW.channel_id;
      ELSIF TG_OP = 'DELETE' THEN
        UPDATE channels SET post_count = GREATEST(0, post_count - 1) WHERE id = OLD.channel_id;
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """,
    "DROP FUNCTION IF EXISTS update_channel_post_count() CASCADE"

    execute """
    CREATE TRIGGER trigger_update_channel_post_count
    AFTER INSERT OR DELETE ON channel_posts
    FOR EACH ROW EXECUTE FUNCTION update_channel_post_count();
    """,
    "DROP TRIGGER IF EXISTS trigger_update_channel_post_count ON channel_posts"

    # Trigger to update post comments_count
    execute """
    CREATE OR REPLACE FUNCTION update_post_comments_count()
    RETURNS TRIGGER AS $$
    BEGIN
      IF TG_OP = 'INSERT' THEN
        UPDATE channel_posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
      ELSIF TG_OP = 'DELETE' THEN
        UPDATE channel_posts SET comments_count = GREATEST(0, comments_count - 1) WHERE id = OLD.post_id;
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """,
    "DROP FUNCTION IF EXISTS update_post_comments_count() CASCADE"

    execute """
    CREATE TRIGGER trigger_update_post_comments_count
    AFTER INSERT OR DELETE ON channel_comments
    FOR EACH ROW EXECUTE FUNCTION update_post_comments_count();
    """,
    "DROP TRIGGER IF EXISTS trigger_update_post_comments_count ON channel_comments"

    # Trigger to update comment replies_count
    execute """
    CREATE OR REPLACE FUNCTION update_comment_replies_count()
    RETURNS TRIGGER AS $$
    BEGIN
      IF TG_OP = 'INSERT' AND NEW.parent_id IS NOT NULL THEN
        UPDATE channel_comments SET replies_count = replies_count + 1 WHERE id = NEW.parent_id;
      ELSIF TG_OP = 'DELETE' AND OLD.parent_id IS NOT NULL THEN
        UPDATE channel_comments SET replies_count = GREATEST(0, replies_count - 1) WHERE id = OLD.parent_id;
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """,
    "DROP FUNCTION IF EXISTS update_comment_replies_count() CASCADE"

    execute """
    CREATE TRIGGER trigger_update_comment_replies_count
    AFTER INSERT OR DELETE ON channel_comments
    FOR EACH ROW EXECUTE FUNCTION update_comment_replies_count();
    """,
    "DROP TRIGGER IF EXISTS trigger_update_comment_replies_count ON channel_comments"

    # Trigger to update post unlocks count
    execute """
    CREATE OR REPLACE FUNCTION update_post_unlocks_count()
    RETURNS TRIGGER AS $$
    BEGIN
      IF TG_OP = 'INSERT' THEN
        UPDATE channel_posts SET unlocks = unlocks + 1 WHERE id = NEW.post_id;
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """,
    "DROP FUNCTION IF EXISTS update_post_unlocks_count() CASCADE"

    execute """
    CREATE TRIGGER trigger_update_post_unlocks_count
    AFTER INSERT ON post_unlocks
    FOR EACH ROW EXECUTE FUNCTION update_post_unlocks_count();
    """,
    "DROP TRIGGER IF EXISTS trigger_update_post_unlocks_count ON post_unlocks"

    # Trigger to increment unread_count when new post is published
    execute """
    CREATE OR REPLACE FUNCTION increment_subscribers_unread()
    RETURNS TRIGGER AS $$
    BEGIN
      UPDATE channel_subscriptions
      SET unread_count = unread_count + 1
      WHERE channel_id = NEW.channel_id;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """,
    "DROP FUNCTION IF EXISTS increment_subscribers_unread() CASCADE"

    execute """
    CREATE TRIGGER trigger_increment_subscribers_unread
    AFTER INSERT ON channel_posts
    FOR EACH ROW EXECUTE FUNCTION increment_subscribers_unread();
    """,
    "DROP TRIGGER IF EXISTS trigger_increment_subscribers_unread ON channel_posts"
  end
end
