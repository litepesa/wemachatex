defmodule WemachatCore.Contexts.Contacts do
  @moduledoc """
  Context for managing contacts, blocked users, and privacy controls.
  """

  import Ecto.Query
  alias WemachatDatabase.Repo
  alias WemachatDatabase.Schemas.{Contact, BlockedUser, User}

  # ==========================================
  # CONTACT MANAGEMENT
  # ==========================================

  @doc """
  Add a user to contacts.
  """
  def add_contact(user_id, contact_user_id, attrs \\ %{}) do
    # Check if already blocked
    if is_blocked?(user_id, contact_user_id) do
      {:error, :blocked}
    else
      %Contact{}
      |> Contact.changeset(Map.merge(attrs, %{
        user_id: user_id,
        contact_user_id: contact_user_id
      }))
      |> Repo.insert()
    end
  end

  @doc """
  Remove a contact.
  """
  def remove_contact(user_id, contact_user_id) do
    case get_contact(user_id, contact_user_id) do
      nil -> {:error, :not_found}
      contact -> Repo.delete(contact)
    end
  end

  @doc """
  Get a specific contact relationship.
  """
  def get_contact(user_id, contact_user_id) do
    Repo.get_by(Contact, user_id: user_id, contact_user_id: contact_user_id)
  end

  @doc """
  Update contact details (display_name, is_favorite, notes).
  """
  def update_contact(user_id, contact_user_id, attrs) do
    case get_contact(user_id, contact_user_id) do
      nil ->
        {:error, :not_found}

      contact ->
        contact
        |> Contact.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  List all contacts for a user with pagination.
  """
  def list_contacts(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)
    include_user = Keyword.get(opts, :include_user, true)

    query =
      from c in Contact,
        where: c.user_id == ^user_id,
        order_by: [desc: c.is_favorite, desc: c.inserted_at],
        limit: ^per_page,
        offset: ^((page - 1) * per_page)

    query =
      if include_user do
        query |> preload(:contact_user)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  List favorite contacts.
  """
  def list_favorites(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)

    from(c in Contact,
      where: c.user_id == ^user_id and c.is_favorite == true,
      order_by: [desc: c.inserted_at],
      limit: ^per_page,
      offset: ^((page - 1) * per_page),
      preload: :contact_user
    )
    |> Repo.all()
  end

  @doc """
  Search contacts by display name or contact user's name.
  """
  def search_contacts(user_id, query_string, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    search_query = "%#{query_string}%"

    from(c in Contact,
      join: u in User,
      on: c.contact_user_id == u.id,
      where: c.user_id == ^user_id,
      where: ilike(c.display_name, ^search_query) or ilike(u.name, ^search_query),
      order_by: [desc: c.is_favorite, desc: c.inserted_at],
      limit: ^per_page,
      offset: ^((page - 1) * per_page),
      preload: :contact_user
    )
    |> Repo.all()
  end

  @doc """
  Check if user B is in user A's contacts.
  """
  def is_contact?(user_id, contact_user_id) do
    Repo.exists?(
      from c in Contact,
        where: c.user_id == ^user_id and c.contact_user_id == ^contact_user_id
    )
  end

  @doc """
  Get contact count for a user.
  """
  def contact_count(user_id) do
    Repo.one(
      from c in Contact,
        where: c.user_id == ^user_id,
        select: count(c.id)
    )
  end

  # ==========================================
  # BLOCKING MANAGEMENT
  # ==========================================

  @doc """
  Block a user.
  """
  def block_user(blocker_id, blocked_id, reason \\ nil) do
    attrs = %{
      blocker_id: blocker_id,
      blocked_id: blocked_id,
      reason: reason
    }

    %BlockedUser{}
    |> BlockedUser.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Unblock a user.
  """
  def unblock_user(blocker_id, blocked_id) do
    case get_block(blocker_id, blocked_id) do
      nil -> {:error, :not_found}
      block -> Repo.delete(block)
    end
  end

  @doc """
  Get a specific block relationship.
  """
  def get_block(blocker_id, blocked_id) do
    Repo.get_by(BlockedUser, blocker_id: blocker_id, blocked_id: blocked_id)
  end

  @doc """
  Check if user A has blocked user B.
  """
  def is_blocked?(blocker_id, blocked_id) do
    Repo.exists?(
      from b in BlockedUser,
        where: b.blocker_id == ^blocker_id and b.blocked_id == ^blocked_id
    )
  end

  @doc """
  Check if there's a mutual block (either direction).
  """
  def is_blocked_mutual?(user_a_id, user_b_id) do
    Repo.exists?(
      from b in BlockedUser,
        where:
          (b.blocker_id == ^user_a_id and b.blocked_id == ^user_b_id) or
            (b.blocker_id == ^user_b_id and b.blocked_id == ^user_a_id)
    )
  end

  @doc """
  List all users blocked by this user.
  """
  def list_blocked_users(blocker_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)

    from(b in BlockedUser,
      where: b.blocker_id == ^blocker_id,
      order_by: [desc: b.inserted_at],
      limit: ^per_page,
      offset: ^((page - 1) * per_page),
      preload: :blocked
    )
    |> Repo.all()
  end

  @doc """
  Get count of blocked users.
  """
  def blocked_count(blocker_id) do
    Repo.one(
      from b in BlockedUser,
        where: b.blocker_id == ^blocker_id,
        select: count(b.id)
    )
  end

  # ==========================================
  # PRIVACY ENFORCEMENT
  # ==========================================

  @doc """
  Check if user A can send a message to user B based on privacy settings.

  Returns:
  - {:ok, :allowed} if messaging is allowed
  - {:error, :blocked} if either user has blocked the other
  - {:error, :privacy_settings} if recipient's settings don't allow it
  """
  def can_message?(sender_id, recipient_id) do
    # Check if blocked (mutual)
    if is_blocked_mutual?(sender_id, recipient_id) do
      {:error, :blocked}
    else
      # Get recipient's privacy settings
      recipient = Repo.get(User, recipient_id)

      if recipient do
        case recipient.who_can_message do
          "everyone" ->
            {:ok, :allowed}

          "contacts" ->
            if is_contact?(recipient_id, sender_id) do
              {:ok, :allowed}
            else
              {:error, :privacy_settings}
            end

          "nobody" ->
            {:error, :privacy_settings}

          _ ->
            {:ok, :allowed}
        end
      else
        {:error, :user_not_found}
      end
    end
  end

  @doc """
  Check if user A can call user B based on privacy settings.
  """
  def can_call?(caller_id, callee_id) do
    # Check if blocked (mutual)
    if is_blocked_mutual?(caller_id, callee_id) do
      {:error, :blocked}
    else
      # Get callee's privacy settings
      callee = Repo.get(User, callee_id)

      if callee do
        case callee.who_can_call do
          "everyone" ->
            {:ok, :allowed}

          "contacts" ->
            if is_contact?(callee_id, caller_id) do
              {:ok, :allowed}
            else
              {:error, :privacy_settings}
            end

          "nobody" ->
            {:error, :privacy_settings}

          _ ->
            {:ok, :allowed}
        end
      else
        {:error, :user_not_found}
      end
    end
  end

  @doc """
  Check if user A can view user B's online status.
  """
  def can_see_online_status?(viewer_id, user_id) do
    # Blocked users cannot see each other's status
    if is_blocked_mutual?(viewer_id, user_id) do
      false
    else
      user = Repo.get(User, user_id)
      user && user.show_online_status
    end
  end

  @doc """
  Update user's privacy settings.
  """
  def update_privacy_settings(user_id, attrs) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      user ->
        user
        |> User.privacy_changeset(attrs)
        |> Repo.update()
    end
  end

  # ==========================================
  # BATCH OPERATIONS
  # ==========================================

  @doc """
  Sync contacts from phone numbers.
  Accepts a list of phone numbers, returns matching users.
  """
  def sync_contacts(user_id, phone_numbers) when is_list(phone_numbers) do
    # Find users by phone numbers
    matching_users =
      from(u in User,
        where: u.phone_number in ^phone_numbers and u.id != ^user_id,
        select: %{id: u.id, phone_number: u.phone_number, name: u.name, profile_image: u.profile_image}
      )
      |> Repo.all()

    # Return users found on the platform
    {:ok, matching_users}
  end

  @doc """
  Bulk add contacts.
  """
  def bulk_add_contacts(user_id, contact_user_ids) when is_list(contact_user_ids) do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

    contacts =
      Enum.map(contact_user_ids, fn contact_user_id ->
        %{
          id: Ecto.UUID.generate(),
          user_id: user_id,
          contact_user_id: contact_user_id,
          is_favorite: false,
          inserted_at: timestamp,
          updated_at: timestamp
        }
      end)

    Repo.insert_all(Contact, contacts,
      on_conflict: :nothing,
      conflict_target: [:user_id, :contact_user_id]
    )
  end
end
