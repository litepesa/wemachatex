defmodule WemachatDatabase.Repo.Migrations.AddGroupTypesAndEnhancedRoles do
  use Ecto.Migration

  def up do
    # Add group_type column to groups table (immutable - defaults to 'private')
    alter table(:groups) do
      add :group_type, :string, default: "private", null: false
      add :admin_count, :integer, default: 0, null: false
      add :subscriber_count, :integer, default: 0, null: false
    end

    # Add constraint to validate group_type values
    execute """
    ALTER TABLE groups
    ADD CONSTRAINT valid_group_type
    CHECK (group_type IN ('private', 'public'))
    """

    # Update existing group_members role constraint to support enhanced roles
    # First drop the old constraint
    execute "ALTER TABLE group_members DROP CONSTRAINT IF EXISTS valid_role_check"

    # Add new constraint with enhanced roles: owner, admin, moderator, member, subscriber
    execute """
    ALTER TABLE group_members
    ADD CONSTRAINT valid_role_check
    CHECK (role IN ('owner', 'admin', 'moderator', 'member', 'subscriber'))
    """

    # Create function to enforce max 16 admins per group
    execute """
    CREATE OR REPLACE FUNCTION check_admin_limit()
    RETURNS TRIGGER AS $$
    DECLARE
      current_admin_count INTEGER;
    BEGIN
      IF NEW.role = 'admin' AND NEW.is_active = true THEN
        SELECT admin_count INTO current_admin_count
        FROM groups
        WHERE id = NEW.group_id;

        IF current_admin_count >= 16 THEN
          RAISE EXCEPTION 'Group cannot have more than 16 admins';
        END IF;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Create trigger to enforce admin limit on INSERT and UPDATE
    execute """
    CREATE TRIGGER enforce_admin_limit
      BEFORE INSERT OR UPDATE ON group_members
      FOR EACH ROW
      EXECUTE FUNCTION check_admin_limit()
    """

    # Create function to update group admin_count
    execute """
    CREATE OR REPLACE FUNCTION update_group_admin_count()
    RETURNS TRIGGER AS $$
    BEGIN
      IF TG_OP = 'INSERT' THEN
        IF NEW.role = 'admin' AND NEW.is_active = true THEN
          UPDATE groups SET admin_count = admin_count + 1 WHERE id = NEW.group_id;
        END IF;
      ELSIF TG_OP = 'UPDATE' THEN
        -- Became admin
        IF OLD.role != 'admin' AND NEW.role = 'admin' AND NEW.is_active = true THEN
          UPDATE groups SET admin_count = admin_count + 1 WHERE id = NEW.group_id;
        -- No longer admin (demoted or deactivated)
        ELSIF OLD.role = 'admin' AND OLD.is_active = true AND
              (NEW.role != 'admin' OR NEW.is_active = false) THEN
          UPDATE groups SET admin_count = admin_count - 1 WHERE id = NEW.group_id;
        END IF;
      ELSIF TG_OP = 'DELETE' THEN
        IF OLD.role = 'admin' AND OLD.is_active = true THEN
          UPDATE groups SET admin_count = admin_count - 1 WHERE id = OLD.group_id;
        END IF;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Create trigger to maintain admin_count
    execute """
    CREATE TRIGGER maintain_admin_count
      AFTER INSERT OR UPDATE OR DELETE ON group_members
      FOR EACH ROW
      EXECUTE FUNCTION update_group_admin_count()
    """

    # Create function to update group subscriber_count (for public groups)
    execute """
    CREATE OR REPLACE FUNCTION update_group_subscriber_count()
    RETURNS TRIGGER AS $$
    BEGIN
      IF TG_OP = 'INSERT' THEN
        IF NEW.role = 'subscriber' AND NEW.is_active = true THEN
          UPDATE groups SET subscriber_count = subscriber_count + 1 WHERE id = NEW.group_id;
        END IF;
      ELSIF TG_OP = 'UPDATE' THEN
        -- Became subscriber
        IF OLD.role != 'subscriber' AND NEW.role = 'subscriber' AND NEW.is_active = true THEN
          UPDATE groups SET subscriber_count = subscriber_count + 1 WHERE id = NEW.group_id;
        -- No longer subscriber
        ELSIF OLD.role = 'subscriber' AND OLD.is_active = true AND
              (NEW.role != 'subscriber' OR NEW.is_active = false) THEN
          UPDATE groups SET subscriber_count = subscriber_count - 1 WHERE id = NEW.group_id;
        END IF;
      ELSIF TG_OP = 'DELETE' THEN
        IF OLD.role = 'subscriber' AND OLD.is_active = true THEN
          UPDATE groups SET subscriber_count = subscriber_count - 1 WHERE id = OLD.group_id;
        END IF;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Create trigger to maintain subscriber_count
    execute """
    CREATE TRIGGER maintain_subscriber_count
      AFTER INSERT OR UPDATE OR DELETE ON group_members
      FOR EACH ROW
      EXECUTE FUNCTION update_group_subscriber_count()
    """

    # Create indexes for better query performance
    create index(:groups, [:group_type])
    create index(:group_members, [:role])
  end

  def down do
    # Drop indexes
    drop index(:groups, [:group_type])
    drop index(:group_members, [:role])

    # Drop triggers
    execute "DROP TRIGGER IF EXISTS maintain_subscriber_count ON group_members"
    execute "DROP TRIGGER IF EXISTS maintain_admin_count ON group_members"
    execute "DROP TRIGGER IF EXISTS enforce_admin_limit ON group_members"

    # Drop functions
    execute "DROP FUNCTION IF EXISTS update_group_subscriber_count()"
    execute "DROP FUNCTION IF EXISTS update_group_admin_count()"
    execute "DROP FUNCTION IF EXISTS check_admin_limit()"

    # Restore old role constraint
    execute "ALTER TABLE group_members DROP CONSTRAINT IF EXISTS valid_role_check"
    execute """
    ALTER TABLE group_members
    ADD CONSTRAINT valid_role_check
    CHECK (role IN ('admin', 'member'))
    """

    # Remove group_type constraint
    execute "ALTER TABLE groups DROP CONSTRAINT IF EXISTS valid_group_type"

    # Remove columns
    alter table(:groups) do
      remove :subscriber_count
      remove :admin_count
      remove :group_type
    end
  end
end
