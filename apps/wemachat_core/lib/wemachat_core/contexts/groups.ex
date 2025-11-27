defmodule WemachatCore.Contexts.Groups do
  @moduledoc """
  The Groups context.
  Handles all business logic for group chat conversations, members, and messages.
  """

  import Ecto.Query, warn: false
  alias WemachatDatabase.Repo
  alias WemachatDatabase.Schemas.{Group, GroupMember, GroupMessage}

  ## GROUPS

  @doc """
  Create a new group.
  Creator is automatically added as admin member.
  """
  def create_group(attrs) do
    Repo.transaction(fn ->
      # Create group
      group =
        %Group{}
        |> Group.create_changeset(attrs)
        |> Repo.insert!()

      # Add creator as admin
      %GroupMember{}
      |> GroupMember.create_changeset(%{
        group_id: group.id,
        user_id: attrs.creator_id,
        role: "admin"
      })
      |> Repo.insert!()

      group
    end)
  end

  @doc """
  Get a single group by ID.
  """
  def get_group(id), do: Repo.get(Group, id)

  @doc """
  Get a single group by ID, raises if not found.
  """
  def get_group!(id), do: Repo.get!(Group, id)

  @doc """
  Get a group with members preloaded.
  """
  def get_group_with_members(id) do
    Group
    |> where([g], g.id == ^id)
    |> preload(:members)
    |> Repo.one()
  end

  @doc """
  List all groups for a user (ordered by last message).
  """
  def list_user_groups(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    Group
    |> join(:inner, [g], gm in GroupMember, on: gm.group_id == g.id)
    |> where([g, gm], gm.user_id == ^user_id and gm.is_active == true and g.is_active == true)
    |> order_by([g], desc: g.last_message_at, desc: g.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Update group details (name, description, image).
  """
  def update_group(%Group{} = group, attrs) do
    group
    |> Group.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft delete a group.
  """
  def deactivate_group(%Group{} = group) do
    group
    |> Group.update_changeset(%{is_active: false})
    |> Repo.update()
  end

  @doc """
  Check if a user is a member of a group.
  """
  def member?(group_id, user_id) do
    GroupMember
    |> where([gm], gm.group_id == ^group_id and gm.user_id == ^user_id and gm.is_active == true)
    |> Repo.exists?()
  end

  @doc """
  Check if a user is an admin of a group.
  """
  def admin?(group_id, user_id) do
    GroupMember
    |> where([gm],
      gm.group_id == ^group_id and
      gm.user_id == ^user_id and
      gm.role == "admin" and
      gm.is_active == true
    )
    |> Repo.exists?()
  end

  ## GROUP MEMBERS

  @doc """
  Add a member to a group.
  Enforces the 512 member limit via database trigger.
  """
  def add_member(attrs) do
    %GroupMember{}
    |> GroupMember.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Add multiple members to a group.
  Returns {:ok, count} on success, {:error, reason} on failure.
  """
  def add_members(group_id, user_ids) when is_list(user_ids) do
    Repo.transaction(fn ->
      Enum.each(user_ids, fn user_id ->
        %GroupMember{}
        |> GroupMember.create_changeset(%{
          group_id: group_id,
          user_id: user_id,
          role: "member"
        })
        |> Repo.insert!()
      end)

      length(user_ids)
    end)
  end

  @doc """
  Remove a member from a group (soft delete).
  """
  def remove_member(group_id, user_id) do
    GroupMember
    |> where([gm], gm.group_id == ^group_id and gm.user_id == ^user_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      member ->
        member
        |> GroupMember.update_changeset(%{is_active: false})
        |> Repo.update()
    end
  end

  @doc """
  Promote a member to admin.
  """
  def promote_to_admin(group_id, user_id) do
    GroupMember
    |> where([gm], gm.group_id == ^group_id and gm.user_id == ^user_id and gm.is_active == true)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      member ->
        member
        |> GroupMember.update_changeset(%{role: "admin"})
        |> Repo.update()
    end
  end

  @doc """
  Demote an admin to regular member.
  """
  def demote_to_member(group_id, user_id) do
    GroupMember
    |> where([gm], gm.group_id == ^group_id and gm.user_id == ^user_id and gm.is_active == true)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      member ->
        member
        |> GroupMember.update_changeset(%{role: "member"})
        |> Repo.update()
    end
  end

  @doc """
  List all active members of a group.
  """
  def list_group_members(group_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)

    GroupMember
    |> where([gm], gm.group_id == ^group_id and gm.is_active == true)
    |> order_by([gm], asc: gm.joined_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Get member count for a group.
  """
  def get_member_count(group_id) do
    case get_group(group_id) do
      nil -> 0
      group -> group.member_count
    end
  end

  ## GROUP MESSAGES

  @doc """
  Send a message in a group.
  Automatically updates group's last message.
  """
  def send_message(attrs) do
    Repo.transaction(fn ->
      # Verify sender is a member
      unless member?(attrs[:group_id], attrs[:sender_id]) do
        Repo.rollback(:not_a_member)
      end

      # Create message
      message =
        %GroupMessage{}
        |> GroupMessage.create_changeset(attrs)
        |> Repo.insert!()

      # Trigger function automatically updates last_message_text and last_message_at
      message
    end)
  end

  @doc """
  Get a single message by ID.
  """
  def get_message(id), do: Repo.get(GroupMessage, id)

  @doc """
  Get a single message by ID, raises if not found.
  """
  def get_message!(id), do: Repo.get!(GroupMessage, id)

  @doc """
  List messages for a group (paginated, newest first).
  """
  def list_group_messages(group_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)

    GroupMessage
    |> where([gm], gm.group_id == ^group_id and gm.is_deleted == false)
    |> order_by([gm], desc: gm.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
    |> Enum.reverse()  # Return in chronological order
  end

  @doc """
  Soft delete a message.
  Only the sender or group admin can delete.
  """
  def delete_message(message_id, user_id) do
    message = get_message!(message_id)

    # Check if user is sender or admin
    can_delete = message.sender_id == user_id or admin?(message.group_id, user_id)

    if can_delete do
      message
      |> GroupMessage.update_changeset(%{is_deleted: true})
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Mark a message as read by a user.
  """
  def mark_message_as_read(message_id, user_id) do
    message = get_message!(message_id)

    case GroupMessage.mark_as_read(message, user_id) do
      {:ok, message} -> {:ok, message}
      changeset ->
        changeset
        |> Repo.update()
    end
  end

  @doc """
  Get unread message count for a user in a group.
  """
  def get_unread_count(group_id, user_id) do
    # Get the member's join time to only count messages after they joined
    member =
      GroupMember
      |> where([gm], gm.group_id == ^group_id and gm.user_id == ^user_id and gm.is_active == true)
      |> Repo.one()

    case member do
      nil -> 0
      member ->
        GroupMessage
        |> where([gm],
          gm.group_id == ^group_id and
          gm.is_deleted == false and
          gm.inserted_at >= ^member.joined_at and
          not fragment("? = ANY(?)", ^user_id, gm.read_by)
        )
        |> Repo.aggregate(:count)
    end
  end

  @doc """
  Search groups by name.
  """
  def search_groups(query, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    search_pattern = "%#{query}%"

    Group
    |> where([g], ilike(g.name, ^search_pattern) and g.is_active == true)
    |> order_by([g], desc: g.member_count)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Leave a group (soft delete membership).
  """
  def leave_group(group_id, user_id) do
    remove_member(group_id, user_id)
  end
end
