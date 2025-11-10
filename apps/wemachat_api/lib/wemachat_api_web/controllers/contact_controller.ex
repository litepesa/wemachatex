defmodule WemachatApiWeb.ContactController do
  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.Contacts
  alias WemachatApiWeb.Plugs.FirebaseAuth

  # Apply Firebase auth to all routes
  plug FirebaseAuth

  # ==========================================
  # CONTACT MANAGEMENT
  # ==========================================

  @doc """
  GET /api/v1/contacts
  List all contacts for the authenticated user.
  """
  def index(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)
    page = Map.get(params, "page", "1") |> String.to_integer()
    per_page = Map.get(params, "per_page", "50") |> String.to_integer()

    contacts = Contacts.list_contacts(user_id, page: page, per_page: per_page)

    json(conn, %{contacts: contacts})
  end

  @doc """
  GET /api/v1/contacts/favorites
  List favorite contacts.
  """
  def favorites(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)
    page = Map.get(params, "page", "1") |> String.to_integer()
    per_page = Map.get(params, "per_page", "50") |> String.to_integer()

    favorites = Contacts.list_favorites(user_id, page: page, per_page: per_page)

    json(conn, %{favorites: favorites})
  end

  @doc """
  GET /api/v1/contacts/search
  Search contacts by name.
  """
  def search(conn, %{"q" => query} = params) do
    user_id = FirebaseAuth.current_user_id(conn)
    page = Map.get(params, "page", "1") |> String.to_integer()
    per_page = Map.get(params, "per_page", "20") |> String.to_integer()

    results = Contacts.search_contacts(user_id, query, page: page, per_page: per_page)

    json(conn, %{results: results})
  end

  def search(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: q"})
  end

  @doc """
  POST /api/v1/contacts
  Add a new contact.
  Body: {"contact_user_id": "...", "display_name": "...", "is_favorite": false}
  """
  def create(conn, %{"contact_user_id" => contact_user_id} = params) do
    user_id = FirebaseAuth.current_user_id(conn)

    attrs = %{
      display_name: Map.get(params, "display_name"),
      is_favorite: Map.get(params, "is_favorite", false),
      notes: Map.get(params, "notes")
    }

    case Contacts.add_contact(user_id, contact_user_id, attrs) do
      {:ok, contact} ->
        conn
        |> put_status(:created)
        |> json(%{contact: contact})

      {:error, :blocked} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Cannot add blocked user as contact"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: format_changeset_errors(changeset)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: contact_user_id"})
  end

  @doc """
  PUT /api/v1/contacts/:contact_user_id
  Update a contact (display name, favorite status, notes).
  """
  def update(conn, %{"contact_user_id" => contact_user_id} = params) do
    user_id = FirebaseAuth.current_user_id(conn)

    attrs =
      params
      |> Map.take(["display_name", "is_favorite", "notes"])
      |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)

    case Contacts.update_contact(user_id, contact_user_id, attrs) do
      {:ok, contact} ->
        json(conn, %{contact: contact})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Contact not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: format_changeset_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/contacts/:contact_user_id
  Remove a contact.
  """
  def delete(conn, %{"contact_user_id" => contact_user_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Contacts.remove_contact(user_id, contact_user_id) do
      {:ok, _contact} ->
        json(conn, %{message: "Contact removed successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Contact not found"})
    end
  end

  # ==========================================
  # BLOCKING
  # ==========================================

  @doc """
  GET /api/v1/contacts/blocked
  List all blocked users.
  """
  def blocked(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)
    page = Map.get(params, "page", "1") |> String.to_integer()
    per_page = Map.get(params, "per_page", "50") |> String.to_integer()

    blocked_users = Contacts.list_blocked_users(user_id, page: page, per_page: per_page)

    json(conn, %{blocked_users: blocked_users})
  end

  @doc """
  POST /api/v1/contacts/block
  Block a user.
  Body: {"blocked_id": "...", "reason": "..."}
  """
  def block(conn, %{"blocked_id" => blocked_id} = params) do
    user_id = FirebaseAuth.current_user_id(conn)
    reason = Map.get(params, "reason")

    case Contacts.block_user(user_id, blocked_id, reason) do
      {:ok, blocked_user} ->
        conn
        |> put_status(:created)
        |> json(%{blocked_user: blocked_user, message: "User blocked successfully"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Blocking failed", details: format_changeset_errors(changeset)})
    end
  end

  def block(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: blocked_id"})
  end

  @doc """
  DELETE /api/v1/contacts/block/:blocked_id
  Unblock a user.
  """
  def unblock(conn, %{"blocked_id" => blocked_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Contacts.unblock_user(user_id, blocked_id) do
      {:ok, _blocked_user} ->
        json(conn, %{message: "User unblocked successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Block relationship not found"})
    end
  end

  # ==========================================
  # PRIVACY SETTINGS
  # ==========================================

  @doc """
  PUT /api/v1/contacts/privacy
  Update privacy settings.
  Body: {"who_can_message": "everyone", "who_can_call": "contacts", "show_online_status": true}
  """
  def update_privacy(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)

    attrs =
      params
      |> Map.take(["who_can_message", "who_can_call", "show_online_status"])
      |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)

    case Contacts.update_privacy_settings(user_id, attrs) do
      {:ok, user} ->
        json(conn, %{
          privacy_settings: %{
            who_can_message: user.who_can_message,
            who_can_call: user.who_can_call,
            show_online_status: user.show_online_status
          }
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: format_changeset_errors(changeset)})
    end
  end

  # ==========================================
  # PRIVACY CHECKS
  # ==========================================

  @doc """
  POST /api/v1/contacts/can-message
  Check if current user can message another user.
  Body: {"recipient_id": "..."}
  """
  def can_message(conn, %{"recipient_id" => recipient_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Contacts.can_message?(user_id, recipient_id) do
      {:ok, :allowed} ->
        json(conn, %{can_message: true, reason: "allowed"})

      {:error, :blocked} ->
        json(conn, %{can_message: false, reason: "blocked"})

      {:error, :privacy_settings} ->
        json(conn, %{can_message: false, reason: "privacy_settings"})

      {:error, :user_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})
    end
  end

  def can_message(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: recipient_id"})
  end

  @doc """
  POST /api/v1/contacts/can-call
  Check if current user can call another user.
  Body: {"callee_id": "..."}
  """
  def can_call(conn, %{"callee_id" => callee_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Contacts.can_call?(user_id, callee_id) do
      {:ok, :allowed} ->
        json(conn, %{can_call: true, reason: "allowed"})

      {:error, :blocked} ->
        json(conn, %{can_call: false, reason: "blocked"})

      {:error, :privacy_settings} ->
        json(conn, %{can_call: false, reason: "privacy_settings"})

      {:error, :user_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})
    end
  end

  def can_call(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: callee_id"})
  end

  # ==========================================
  # BATCH OPERATIONS
  # ==========================================

  @doc """
  POST /api/v1/contacts/sync
  Sync contacts from phone numbers.
  Body: {"phone_numbers": ["254XXXXXXXXX", "254YYYYYYYYY", ...]}
  """
  def sync(conn, %{"phone_numbers" => phone_numbers}) when is_list(phone_numbers) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Contacts.sync_contacts(user_id, phone_numbers) do
      {:ok, matching_users} ->
        json(conn, %{
          users: matching_users,
          total: length(matching_users),
          message: "Contact sync completed"
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Sync failed", reason: inspect(reason)})
    end
  end

  def sync(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing or invalid parameter: phone_numbers (must be array)"})
  end

  # ==========================================
  # HELPERS
  # ==========================================

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
