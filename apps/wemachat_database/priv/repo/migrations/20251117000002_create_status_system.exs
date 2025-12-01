defmodule WemachatDatabase.Repo.Migrations.CreateStatusSystem do
  use Ecto.Migration

  def up do
    # Create statuses table
    create table(:statuses, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, :string, null: false
      add :content, :text
      add :media_url, :string
      add :media_type, :string, null: false, default: "text"
      add :thumbnail_url, :string
      add :text_background, :string
      add :visibility, :string, null: false, default: "all"
      add :visible_to, {:array, :string}, default: []
      add :hidden_from, {:array, :string}, default: []
      add :duration_seconds, :integer
      add :views_count, :integer, default: 0, null: false
      add :likes_count, :integer, default: 0, null: false
      add :gifts_count, :integer, default: 0, null: false
      add :is_deleted, :boolean, default: false, null: false
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for statuses
    create index(:statuses, [:user_id])
    create index(:statuses, [:expires_at])
    create index(:statuses, [:is_deleted])
    create index(:statuses, [:user_id, :is_deleted, :expires_at])

    # Create status_views table
    create table(:status_views, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :status_id, references(:statuses, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, :string, null: false
      add :viewed_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for status_views
    create index(:status_views, [:status_id])
    create index(:status_views, [:user_id])
    create unique_index(:status_views, [:status_id, :user_id])

    # Create status_likes table
    create table(:status_likes, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :status_id, references(:statuses, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for status_likes
    create index(:status_likes, [:status_id])
    create index(:status_likes, [:user_id])
    create unique_index(:status_likes, [:status_id, :user_id])

    # Trigger function to update views_count
    execute """
    CREATE OR REPLACE FUNCTION update_status_views_count()
    RETURNS TRIGGER AS $$
    BEGIN
      IF TG_OP = 'INSERT' THEN
        UPDATE statuses
        SET views_count = views_count + 1
        WHERE id = NEW.status_id;
        RETURN NEW;
      ELSIF TG_OP = 'DELETE' THEN
        UPDATE statuses
        SET views_count = GREATEST(0, views_count - 1)
        WHERE id = OLD.status_id;
        RETURN OLD;
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Trigger for views_count
    execute """
    CREATE TRIGGER status_views_count_trigger
    AFTER INSERT OR DELETE ON status_views
    FOR EACH ROW
    EXECUTE FUNCTION update_status_views_count();
    """

    # Trigger function to update likes_count
    execute """
    CREATE OR REPLACE FUNCTION update_status_likes_count()
    RETURNS TRIGGER AS $$
    BEGIN
      IF TG_OP = 'INSERT' THEN
        UPDATE statuses
        SET likes_count = likes_count + 1
        WHERE id = NEW.status_id;
        RETURN NEW;
      ELSIF TG_OP = 'DELETE' THEN
        UPDATE statuses
        SET likes_count = GREATEST(0, likes_count - 1)
        WHERE id = OLD.status_id;
        RETURN OLD;
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Trigger for likes_count
    execute """
    CREATE TRIGGER status_likes_count_trigger
    AFTER INSERT OR DELETE ON status_likes
    FOR EACH ROW
    EXECUTE FUNCTION update_status_likes_count();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS status_likes_count_trigger ON status_likes"
    execute "DROP TRIGGER IF EXISTS status_views_count_trigger ON status_views"

    execute "DROP FUNCTION IF EXISTS update_status_likes_count();"
    execute "DROP FUNCTION IF EXISTS update_status_views_count();"

    drop table(:status_likes)
    drop table(:status_views)
    drop table(:statuses)
  end
end
