defmodule WemachatDatabase.Repo.Migrations.CreateGroupPostsAndComments do
  use Ecto.Migration

  def up do
    # Create group_posts table for public groups
    create table(:group_posts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false
      add :author_id, :string, null: false
      add :content_type, :string, default: "text", null: false
      add :text, :text
      add :media_url, :text
      add :media_urls, {:array, :text}
      add :media_thumbnail_url, :text
      add :media_type, :string
      add :likes, :integer, default: 0, null: false
      add :comments_count, :integer, default: 0, null: false
      add :views, :integer, default: 0, null: false
      add :is_pinned, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    # Add constraint for valid content types
    execute """
    ALTER TABLE group_posts
    ADD CONSTRAINT valid_content_type
    CHECK (content_type IN ('text', 'image', 'video', 'audio', 'document'))
    """

    # Create group_post_comments table with threaded comment support
    create table(:group_post_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :post_id, references(:group_posts, type: :binary_id, on_delete: :delete_all), null: false
      add :author_id, :string, null: false
      add :parent_id, references(:group_post_comments, type: :binary_id, on_delete: :delete_all)
      add :text, :text, null: false
      add :media_url, :text
      add :media_type, :string
      add :path, {:array, :binary_id}, default: []
      add :depth, :integer, default: 0, null: false
      add :likes, :integer, default: 0, null: false
      add :replies_count, :integer, default: 0, null: false
      add :is_pinned, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    # Add constraint for valid media types in comments
    execute """
    ALTER TABLE group_post_comments
    ADD CONSTRAINT valid_media_type
    CHECK (media_type IS NULL OR media_type IN ('image', 'video'))
    """

    # Create indexes for group_posts
    create index(:group_posts, [:group_id])
    create index(:group_posts, [:author_id])
    create index(:group_posts, [:inserted_at])
    create index(:group_posts, [:is_pinned, :inserted_at])

    # Create indexes for group_post_comments
    create index(:group_post_comments, [:post_id])
    create index(:group_post_comments, [:parent_id])
    create index(:group_post_comments, [:author_id])
    create index(:group_post_comments, [:path], using: :gin)

    # Create function to auto-increment comment counts
    execute """
    CREATE OR REPLACE FUNCTION increment_group_post_comment_counts()
    RETURNS TRIGGER AS $$
    BEGIN
      -- Increment post's comments_count
      UPDATE group_posts
      SET comments_count = comments_count + 1
      WHERE id = NEW.post_id;

      -- If this is a reply (has parent), increment parent's replies_count
      IF NEW.parent_id IS NOT NULL THEN
        UPDATE group_post_comments
        SET replies_count = replies_count + 1
        WHERE id = NEW.parent_id;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Create trigger to auto-increment comment counts on INSERT
    execute """
    CREATE TRIGGER auto_increment_comment_counts
      AFTER INSERT ON group_post_comments
      FOR EACH ROW
      EXECUTE FUNCTION increment_group_post_comment_counts()
    """

    # Create function to auto-decrement comment counts on DELETE
    execute """
    CREATE OR REPLACE FUNCTION decrement_group_post_comment_counts()
    RETURNS TRIGGER AS $$
    BEGIN
      -- Decrement post's comments_count
      UPDATE group_posts
      SET comments_count = comments_count - 1
      WHERE id = OLD.post_id;

      -- If this was a reply, decrement parent's replies_count
      IF OLD.parent_id IS NOT NULL THEN
        UPDATE group_post_comments
        SET replies_count = replies_count - 1
        WHERE id = OLD.parent_id;
      END IF;

      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Create trigger to auto-decrement comment counts on DELETE
    execute """
    CREATE TRIGGER auto_decrement_comment_counts
      AFTER DELETE ON group_post_comments
      FOR EACH ROW
      EXECUTE FUNCTION decrement_group_post_comment_counts()
    """
  end

  def down do
    # Drop triggers
    execute "DROP TRIGGER IF EXISTS auto_decrement_comment_counts ON group_post_comments"
    execute "DROP TRIGGER IF EXISTS auto_increment_comment_counts ON group_post_comments"

    # Drop functions
    execute "DROP FUNCTION IF EXISTS decrement_group_post_comment_counts()"
    execute "DROP FUNCTION IF EXISTS increment_group_post_comment_counts()"

    # Drop tables (indexes will be dropped automatically)
    drop table(:group_post_comments)
    drop table(:group_posts)
  end
end
