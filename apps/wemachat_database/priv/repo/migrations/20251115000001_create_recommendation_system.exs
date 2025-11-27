defmodule WemachatDatabase.Repo.Migrations.CreateRecommendationSystem do
  use Ecto.Migration

  def up do
    # ==================== VIDEO VIEWS TABLE ====================
    # Track which videos users have watched to prevent showing them again
    create table(:video_views, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :string), null: false
      add :video_id, references(:videos, on_delete: :delete_all, type: :binary_id), null: false
      add :watched_at, :utc_datetime_usec, null: false
      add :watch_duration_seconds, :integer, default: 0
      add :completed, :boolean, default: false

      timestamps(type: :utc_datetime_usec)
    end

    # Composite index for fast "already seen" lookups
    create unique_index(:video_views, [:user_id, :video_id])
    create index(:video_views, [:user_id])
    create index(:video_views, [:video_id])
    create index(:video_views, [:watched_at])

    # ==================== USER MODERATION FIELDS ====================
    # Add admin control fields to users table
    alter table(:users) do
      # Moderation flags
      add :is_muted, :boolean, default: false, null: false
      add :is_shadowbanned, :boolean, default: false, null: false

      # Reach control (0.0 = no reach, 1.0 = normal, 2.0 = double reach)
      add :reach_multiplier, :decimal, precision: 3, scale: 2, default: 1.0, null: false

      # Content categorization (admin-assigned)
      add :creator_content_type, :string  # What they create: "comedy", "music", "education", etc.
      add :interest_type, :string  # What they watch: "comedy", "music", "education", etc.

      # Engagement tracking
      add :last_active_at, :utc_datetime_usec
      add :engagement_score, :integer, default: 0
    end

    # Indexes for filtering and queries
    create index(:users, [:is_muted])
    create index(:users, [:is_shadowbanned])
    create index(:users, [:reach_multiplier])
    create index(:users, [:creator_content_type])
    create index(:users, [:interest_type])
    create index(:users, [:last_active_at])

    # ==================== VIDEO ADMIN CONTROL FIELDS ====================
    # Add recommendation and targeting fields to videos table
    alter table(:videos) do
      # Admin boost score (0-100, higher = more visibility)
      add :admin_boost_score, :integer, default: 0, null: false

      # Geo-targeting (null = show to everyone)
      add :target_counties, {:array, :string}
      add :target_constituencies, {:array, :string}
      add :target_wards, {:array, :string}

      # Visibility control
      add :is_pinned, :boolean, default: false
      add :visibility_level, :string, default: "public"  # "public", "limited", "hidden"

      # Calculated recommendation score (updated by trigger or background job)
      add :recommendation_score, :decimal, precision: 10, scale: 2, default: 0.0
    end

    # Indexes for recommendation queries
    create index(:videos, [:admin_boost_score])
    create index(:videos, [:recommendation_score])
    create index(:videos, [:is_pinned])
    create index(:videos, [:visibility_level])
    create index(:videos, [:target_counties])

    # Composite index for recommendation sorting
    create index(:videos, [:recommendation_score, :inserted_at])
    create index(:videos, [:admin_boost_score, :inserted_at])

    # ==================== UPDATE EXISTING DATA ====================
    # Set default values for existing users
    execute """
    UPDATE users
    SET
      is_muted = false,
      is_shadowbanned = false,
      reach_multiplier = 1.0,
      last_active_at = COALESCE(last_active_at, updated_at),
      engagement_score = 0
    WHERE is_muted IS NULL
    """

    # Set default values for existing videos
    execute """
    UPDATE videos
    SET
      admin_boost_score = 0,
      is_pinned = false,
      visibility_level = 'public',
      recommendation_score = 0.0
    WHERE admin_boost_score IS NULL
    """
  end

  def down do
    # Drop video views table
    drop index(:video_views, [:user_id, :video_id])
    drop index(:video_views, [:user_id])
    drop index(:video_views, [:video_id])
    drop index(:video_views, [:watched_at])
    drop table(:video_views)

    # Drop user indexes
    drop index(:users, [:is_muted])
    drop index(:users, [:is_shadowbanned])
    drop index(:users, [:reach_multiplier])
    drop index(:users, [:creator_content_type])
    drop index(:users, [:interest_type])
    drop index(:users, [:last_active_at])

    # Drop video indexes
    drop index(:videos, [:admin_boost_score])
    drop index(:videos, [:recommendation_score])
    drop index(:videos, [:is_pinned])
    drop index(:videos, [:visibility_level])
    drop index(:videos, [:target_counties])
    drop index(:videos, [:recommendation_score, :inserted_at])
    drop index(:videos, [:admin_boost_score, :inserted_at])

    # Remove user columns
    alter table(:users) do
      remove :is_muted
      remove :is_shadowbanned
      remove :reach_multiplier
      remove :creator_content_type
      remove :interest_type
      remove :last_active_at
      remove :engagement_score
    end

    # Remove video columns
    alter table(:videos) do
      remove :admin_boost_score
      remove :target_counties
      remove :target_constituencies
      remove :target_wards
      remove :is_pinned
      remove :visibility_level
      remove :recommendation_score
    end
  end
end
