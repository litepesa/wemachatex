defmodule WemachatDatabase.Repo.Migrations.CreateMoments do
  use Ecto.Migration

  def change do
    # Posts table - User status updates / moments (like Facebook posts or WeChat Moments)
    create table(:posts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :string, on_delete: :delete_all), null: false

      # Content
      add :content_text, :text
      add :media_urls, {:array, :string}, default: []

      # Media type for the post (if has media)
      add :media_type, :string # "images", "video", "mixed"

      # Privacy settings
      add :visibility, :string, default: "public", null: false # "public", "friends", "private"

      # Engagement counters
      add :likes_count, :integer, default: 0, null: false
      add :comments_count, :integer, default: 0, null: false
      add :shares_count, :integer, default: 0, null: false

      # Soft delete
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for posts
    create index(:posts, [:user_id, :inserted_at])
    create index(:posts, [:is_active, :visibility, :inserted_at])
    create index(:posts, [:inserted_at])

    # Check constraint - post must have text or media
    create constraint(:posts, :post_content,
             check: "content_text IS NOT NULL OR array_length(media_urls, 1) > 0"
           )

    # Post likes table
    create table(:post_likes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :string, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Unique constraint - one like per user per post
    create unique_index(:post_likes, [:post_id, :user_id])
    create index(:post_likes, [:user_id])

    # Post comments table
    create table(:post_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :string, on_delete: :delete_all), null: false

      # Comment content
      add :comment_text, :text, null: false
      add :media_url, :string

      # Soft delete
      add :is_deleted, :boolean, default: false, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for comments
    create index(:post_comments, [:post_id, :inserted_at])
    create index(:post_comments, [:user_id])
    create index(:post_comments, [:is_deleted])
  end
end
