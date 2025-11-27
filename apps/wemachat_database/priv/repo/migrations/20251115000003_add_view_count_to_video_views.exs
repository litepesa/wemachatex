defmodule WemachatDatabase.Repo.Migrations.AddViewCountToVideoViews do
  use Ecto.Migration

  def up do
    # Add view_count field to track how many times a featured video has been shown
    alter table(:video_views) do
      add :view_count, :integer, default: 1, null: false
    end

    # Set view_count = 1 for all existing records
    execute """
    UPDATE video_views SET view_count = 1 WHERE view_count IS NULL
    """
  end

  def down do
    alter table(:video_views) do
      remove :view_count
    end
  end
end
