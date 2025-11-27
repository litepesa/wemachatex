defmodule WemachatDatabase.Repo.Migrations.CreateGroupChatSystem do
  use Ecto.Migration

  def up do
    # Create groups table
    create table(:groups, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :description, :text
      add :group_image_url, :string
      add :creator_id, :string, null: false
      add :member_count, :integer, default: 1, null: false
      add :max_members, :integer, default: 512, null: false
      add :last_message_text, :text
      add :last_message_at, :utc_datetime_usec
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Create group_members table
    create table(:group_members, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :group_id, references(:groups, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, :string, null: false
      add :role, :string, default: "member", null: false  # admin, member
      add :joined_at, :utc_datetime_usec, null: false, default: fragment("NOW()")
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Create group_messages table
    create table(:group_messages, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :group_id, references(:groups, type: :uuid, on_delete: :delete_all), null: false
      add :sender_id, :string, null: false
      add :message_text, :text
      add :media_url, :string
      add :media_type, :string  # image, video, audio, document
      add :is_deleted, :boolean, default: false, null: false
      add :read_by, {:array, :string}, default: []

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for groups
    create index(:groups, [:creator_id])
    create index(:groups, [:is_active])
    create index(:groups, [:last_message_at])

    # Indexes for group_members
    create unique_index(:group_members, [:group_id, :user_id],
      name: :group_members_group_user_unique,
      where: "is_active = true"
    )
    create index(:group_members, [:user_id])
    create index(:group_members, [:group_id])
    create index(:group_members, [:is_active])

    # Indexes for group_messages
    create index(:group_messages, [:group_id, :inserted_at])
    create index(:group_messages, [:sender_id])
    create index(:group_messages, [:is_deleted])

    # Trigger to update member_count when members are added/removed
    execute """
    CREATE OR REPLACE FUNCTION update_group_member_count()
    RETURNS TRIGGER AS $$
    BEGIN
      IF TG_OP = 'INSERT' AND NEW.is_active = true THEN
        UPDATE groups
        SET member_count = member_count + 1
        WHERE id = NEW.group_id;
      ELSIF TG_OP = 'UPDATE' AND OLD.is_active = true AND NEW.is_active = false THEN
        UPDATE groups
        SET member_count = member_count - 1
        WHERE id = NEW.group_id;
      ELSIF TG_OP = 'UPDATE' AND OLD.is_active = false AND NEW.is_active = true THEN
        UPDATE groups
        SET member_count = member_count + 1
        WHERE id = NEW.group_id;
      ELSIF TG_OP = 'DELETE' AND OLD.is_active = true THEN
        UPDATE groups
        SET member_count = member_count - 1
        WHERE id = OLD.group_id;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER group_member_count_trigger
    AFTER INSERT OR UPDATE OR DELETE ON group_members
    FOR EACH ROW
    EXECUTE FUNCTION update_group_member_count();
    """

    # Trigger to update last_message info when a message is sent
    execute """
    CREATE OR REPLACE FUNCTION update_group_last_message()
    RETURNS TRIGGER AS $$
    BEGIN
      IF TG_OP = 'INSERT' AND NEW.is_deleted = false THEN
        UPDATE groups
        SET last_message_text = NEW.message_text,
            last_message_at = NEW.inserted_at
        WHERE id = NEW.group_id;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER group_last_message_trigger
    AFTER INSERT ON group_messages
    FOR EACH ROW
    EXECUTE FUNCTION update_group_last_message();
    """

    # Constraint to enforce 512 member limit
    execute """
    CREATE OR REPLACE FUNCTION check_group_member_limit()
    RETURNS TRIGGER AS $$
    DECLARE
      current_count INTEGER;
      max_limit INTEGER;
    BEGIN
      SELECT member_count, max_members INTO current_count, max_limit
      FROM groups
      WHERE id = NEW.group_id;

      IF current_count >= max_limit THEN
        RAISE EXCEPTION 'Group has reached maximum member limit of %', max_limit;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER check_group_member_limit_trigger
    BEFORE INSERT ON group_members
    FOR EACH ROW
    EXECUTE FUNCTION check_group_member_limit();
    """
  end

  def down do
    # Drop triggers
    execute "DROP TRIGGER IF EXISTS check_group_member_limit_trigger ON group_members"
    execute "DROP TRIGGER IF EXISTS group_last_message_trigger ON group_messages"
    execute "DROP TRIGGER IF EXISTS group_member_count_trigger ON group_members"

    # Drop functions
    execute "DROP FUNCTION IF EXISTS check_group_member_limit()"
    execute "DROP FUNCTION IF EXISTS update_group_last_message()"
    execute "DROP FUNCTION IF EXISTS update_group_member_count()"

    # Drop tables (cascade will handle foreign keys)
    drop table(:group_messages)
    drop table(:group_members)
    drop table(:groups)
  end
end
