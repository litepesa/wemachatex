defmodule WemachatDatabase.Repo.Migrations.CreateMarketplaceSystem do
  use Ecto.Migration

  def up do
    # Enable pg_trgm extension for fuzzy search
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    # Create marketplace_items table (clone of videos but NO expires_at field)
    create table(:marketplace_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # User/Seller info
      add :user_id, :string, null: false
      add :user_name, :string, null: false
      add :user_image, :string

      # Media URLs (same as videos - can be video OR images)
      add :video_url, :string
      add :thumbnail_url, :string

      # Content
      add :caption, :text
      add :tags, {:array, :string}, default: []

      # Price (main difference - marketplace items have price)
      add :price, :decimal, precision: 12, scale: 2, default: 0.0, null: false

      # Engagement metrics
      add :views, :integer, default: 0, null: false
      add :likes, :integer, default: 0, null: false
      add :comments, :integer, default: 0, null: false
      add :shares, :integer, default: 0, null: false

      # Status flags
      add :is_active, :boolean, default: true, null: false
      add :is_featured, :boolean, default: false, null: false
      add :is_verified, :boolean, default: false, null: false

      # Boost system (same as videos)
      add :is_boosted, :boolean, default: false
      add :boost_tier, :string, default: "none"
      add :super_boost, :boolean, default: false

      # Multiple Images Support (same as videos)
      add :is_multiple_images, :boolean, default: false
      add :image_urls, {:array, :string}, default: []

      # NO EXPIRY FIELD (main difference from videos)

      # Recommendation & Admin control (same as videos)
      add :admin_boost_score, :integer, default: 0
      add :target_counties, {:array, :string}
      add :target_constituencies, {:array, :string}
      add :target_wards, {:array, :string}
      add :is_pinned, :boolean, default: false
      add :visibility_level, :string, default: "public"
      add :recommendation_score, :decimal, precision: 10, scale: 2, default: 0.0

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for marketplace_items (same pattern as videos)
    create index(:marketplace_items, [:user_id])
    create index(:marketplace_items, [:is_active])
    create index(:marketplace_items, [:is_featured])
    create index(:marketplace_items, [:inserted_at])

    # Composite index for trending (engagement-based)
    create index(:marketplace_items, [:likes, :views, :inserted_at],
      name: :marketplace_items_trending_index
    )

    # Full-text search on caption (trigram for fuzzy search)
    execute """
    CREATE INDEX marketplace_items_caption_trgm_index ON marketplace_items
    USING gin (caption gin_trgm_ops)
    """

    # GIN index for tags array
    create index(:marketplace_items, [:tags], using: :gin)

    # GIN indexes for geo-targeting arrays
    create index(:marketplace_items, [:target_counties], using: :gin)
    create index(:marketplace_items, [:target_constituencies], using: :gin)
    create index(:marketplace_items, [:target_wards], using: :gin)

    # Create marketplace_likes table (same as video_likes)
    create table(:marketplace_likes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :item_id, references(:marketplace_items, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for likes
    create unique_index(:marketplace_likes, [:item_id, :user_id])
    create index(:marketplace_likes, [:user_id])

    # Create marketplace_comments table (same as video_comments)
    create table(:marketplace_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :item_id, references(:marketplace_items, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, :string, null: false
      add :user_name, :string, null: false
      add :user_image, :string

      add :comment_text, :text, null: false
      add :media_url, :string

      # Support for replies
      add :replied_to_comment_id, :binary_id
      add :parent_comment_id, :binary_id
      add :replied_to_author_name, :string

      # Comment features
      add :likes_count, :integer, default: 0
      add :is_reply, :boolean, default: false
      add :is_pinned, :boolean, default: false
      add :is_edited, :boolean, default: false
      add :is_active, :boolean, default: true

      # Support for image attachments in comments
      add :image_urls, {:array, :string}, default: []

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for comments
    create index(:marketplace_comments, [:item_id])
    create index(:marketplace_comments, [:user_id])
    create index(:marketplace_comments, [:inserted_at])
    create index(:marketplace_comments, [:parent_comment_id])

    # Trigger function to auto-increment item likes count
    execute """
    CREATE OR REPLACE FUNCTION increment_marketplace_item_likes()
    RETURNS TRIGGER AS $$
    BEGIN
      UPDATE marketplace_items
      SET likes = likes + 1
      WHERE id = NEW.item_id;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER marketplace_item_likes_insert
    AFTER INSERT ON marketplace_likes
    FOR EACH ROW
    EXECUTE FUNCTION increment_marketplace_item_likes();
    """

    # Trigger function to auto-decrement item likes count
    execute """
    CREATE OR REPLACE FUNCTION decrement_marketplace_item_likes()
    RETURNS TRIGGER AS $$
    BEGIN
      UPDATE marketplace_items
      SET likes = likes - 1
      WHERE id = OLD.item_id AND likes > 0;
      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER marketplace_item_likes_delete
    AFTER DELETE ON marketplace_likes
    FOR EACH ROW
    EXECUTE FUNCTION decrement_marketplace_item_likes();
    """

    # Trigger function to auto-increment item comments count
    execute """
    CREATE OR REPLACE FUNCTION increment_marketplace_item_comments()
    RETURNS TRIGGER AS $$
    BEGIN
      UPDATE marketplace_items
      SET comments = comments + 1
      WHERE id = NEW.item_id;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER marketplace_item_comments_insert
    AFTER INSERT ON marketplace_comments
    FOR EACH ROW
    EXECUTE FUNCTION increment_marketplace_item_comments();
    """

    # Trigger function to auto-decrement item comments count
    execute """
    CREATE OR REPLACE FUNCTION decrement_marketplace_item_comments()
    RETURNS TRIGGER AS $$
    BEGIN
      UPDATE marketplace_items
      SET comments = comments - 1
      WHERE id = OLD.item_id AND comments > 0;
      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER marketplace_item_comments_delete
    AFTER DELETE ON marketplace_comments
    FOR EACH ROW
    EXECUTE FUNCTION decrement_marketplace_item_comments();
    """
  end

  def down do
    # Drop triggers
    execute "DROP TRIGGER IF EXISTS marketplace_item_comments_delete ON marketplace_comments"
    execute "DROP TRIGGER IF EXISTS marketplace_item_comments_insert ON marketplace_comments"
    execute "DROP TRIGGER IF EXISTS marketplace_item_likes_delete ON marketplace_likes"
    execute "DROP TRIGGER IF EXISTS marketplace_item_likes_insert ON marketplace_likes"

    # Drop trigger functions
    execute "DROP FUNCTION IF EXISTS decrement_marketplace_item_comments()"
    execute "DROP FUNCTION IF EXISTS increment_marketplace_item_comments()"
    execute "DROP FUNCTION IF EXISTS decrement_marketplace_item_likes()"
    execute "DROP FUNCTION IF EXISTS increment_marketplace_item_likes()"

    # Drop tables
    drop table(:marketplace_comments)
    drop table(:marketplace_likes)
    drop table(:marketplace_items)
  end
end
