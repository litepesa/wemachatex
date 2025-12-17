defmodule WemachatApiWeb.GroupController do
  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.Groups
  alias WemachatApiWeb.Plugs.FirebaseAuth

  plug FirebaseAuth

  @doc """
  Create a new group.
  POST /api/v1/groups
  Body: {name, description?, group_image_url?, group_type (private|public)}
  Note: group_type is immutable after creation
  """
  def create(conn, params) do
    user_id = conn.assigns[:current_user_id]

    attrs = %{
      name: params["name"],
      description: params["description"],
      group_image_url: params["group_image_url"],
      group_type: params["group_type"] || "private",
      creator_id: user_id
    }

    case Groups.create_group(attrs) do
      {:ok, group} ->
        conn
        |> put_status(:created)
        |> json(group)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create group", details: translate_errors(changeset)})
    end
  end

  @doc """
  Get a single group by ID.
  GET /api/v1/groups/:id
  """
  def show(conn, %{"id" => id}) do
    user_id = conn.assigns[:current_user_id]

    case Groups.get_group(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Group not found"})

      group ->
        # Verify user is a member
        if Groups.member?(id, user_id) do
          json(conn, group)
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "You are not a member of this group"})
        end
    end
  end

  @doc """
  List all groups for the authenticated user.
  GET /api/v1/groups
  Query params: page, per_page, type (private|public)
  """
  def index(conn, params) do
    user_id = conn.assigns[:current_user_id]

    opts = [
      page: Map.get(params, "page", "1") |> String.to_integer(),
      per_page: Map.get(params, "perPage", "20") |> String.to_integer(),
      type: Map.get(params, "type")
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    groups = Groups.list_user_groups(user_id, opts)
    json(conn, groups)
  end

  @doc """
  Update group details.
  PUT /api/v1/groups/:id
  Body: {name?, description?, group_image_url?}
  """
  def update(conn, %{"id" => id} = params) do
    user_id = conn.assigns[:current_user_id]

    # Verify user is admin
    unless Groups.admin?(id, user_id) do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Only group admins can update group details"})
    else
      case Groups.get_group(id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Group not found"})

        group ->
          attrs = %{
            name: params["name"],
            description: params["description"],
            group_image_url: params["group_image_url"]
          }
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()

          case Groups.update_group(group, attrs) do
            {:ok, updated_group} ->
              json(conn, updated_group)

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Failed to update group", details: translate_errors(changeset)})
          end
      end
    end
  end

  @doc """
  Delete/deactivate a group.
  DELETE /api/v1/groups/:id
  """
  def delete(conn, %{"id" => id}) do
    user_id = conn.assigns[:current_user_id]

    # Verify user is admin
    unless Groups.admin?(id, user_id) do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Only group admins can delete the group"})
    else
      case Groups.get_group(id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Group not found"})

        group ->
          case Groups.deactivate_group(group) do
            {:ok, _group} ->
              conn
              |> put_status(:no_content)
              |> json(%{})

            {:error, _changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Failed to delete group"})
          end
      end
    end
  end

  @doc """
  Add members to a group.
  POST /api/v1/groups/:id/members
  Body: {user_ids: [string]}
  """
  def add_members(conn, %{"id" => group_id, "user_ids" => user_ids}) when is_list(user_ids) do
    user_id = conn.assigns[:current_user_id]

    # Verify user is admin
    unless Groups.admin?(group_id, user_id) do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Only group admins can add members"})
    else
      case Groups.add_members(group_id, user_ids) do
        {:ok, count} ->
          json(conn, %{message: "Successfully added #{count} members"})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to add members", reason: inspect(reason)})
      end
    end
  end

  @doc """
  Remove a member from a group.
  DELETE /api/v1/groups/:id/members/:user_id
  """
  def remove_member(conn, %{"id" => group_id, "user_id" => target_user_id}) do
    user_id = conn.assigns[:current_user_id]

    # User can remove themselves or admin can remove others
    can_remove = user_id == target_user_id or Groups.admin?(group_id, user_id)

    unless can_remove do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "You don't have permission to remove this member"})
    else
      case Groups.remove_member(group_id, target_user_id) do
        {:ok, _member} ->
          json(conn, %{message: "Member removed successfully"})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Member not found in this group"})

        {:error, _changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to remove member"})
      end
    end
  end

  @doc """
  List all members of a group.
  GET /api/v1/groups/:id/members
  Query params: page, per_page
  """
  def list_members(conn, %{"id" => group_id} = params) do
    user_id = conn.assigns[:current_user_id]

    # Verify user is a member
    unless Groups.member?(group_id, user_id) do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "You are not a member of this group"})
    else
      opts = [
        page: Map.get(params, "page", "1") |> String.to_integer(),
        per_page: Map.get(params, "perPage", "50") |> String.to_integer()
      ]

      members = Groups.list_group_members(group_id, opts)
      json(conn, members)
    end
  end

  @doc """
  Promote a member to admin.
  POST /api/v1/groups/:id/members/:user_id/promote
  """
  def promote_member(conn, %{"id" => group_id, "user_id" => target_user_id}) do
    user_id = conn.assigns[:current_user_id]

    # Verify user is admin
    unless Groups.admin?(group_id, user_id) do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Only group admins can promote members"})
    else
      case Groups.promote_to_admin(group_id, target_user_id) do
        {:ok, _member} ->
          json(conn, %{message: "Member promoted to admin"})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Member not found in this group"})

        {:error, _changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to promote member"})
      end
    end
  end

  @doc """
  Demote an admin to regular member.
  POST /api/v1/groups/:id/members/:user_id/demote
  """
  def demote_member(conn, %{"id" => group_id, "user_id" => target_user_id}) do
    user_id = conn.assigns[:current_user_id]

    # Verify user is admin
    unless Groups.admin?(group_id, user_id) do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Only group admins can demote members"})
    else
      case Groups.demote_to_member(group_id, target_user_id) do
        {:ok, _member} ->
          json(conn, %{message: "Admin demoted to member"})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Member not found in this group"})

        {:error, _changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to demote member"})
      end
    end
  end

  @doc """
  Send a message in a group.
  POST /api/v1/groups/:id/messages
  Body: {message_text?, media_url?, media_type?}
  """
  def send_message(conn, %{"id" => group_id} = params) do
    user_id = conn.assigns[:current_user_id]

    attrs = %{
      group_id: group_id,
      sender_id: user_id,
      message_text: params["message_text"],
      media_url: params["media_url"],
      media_type: params["media_type"]
    }

    case Groups.send_message(attrs) do
      {:ok, message} ->
        conn
        |> put_status(:created)
        |> json(message)

      {:error, :not_a_member} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You must be a member to send messages"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to send message", details: translate_errors(changeset)})
    end
  end

  @doc """
  Get messages for a group.
  GET /api/v1/groups/:id/messages
  Query params: page, per_page
  """
  def list_messages(conn, %{"id" => group_id} = params) do
    user_id = conn.assigns[:current_user_id]

    # Verify user is a member
    unless Groups.member?(group_id, user_id) do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "You are not a member of this group"})
    else
      opts = [
        page: Map.get(params, "page", "1") |> String.to_integer(),
        per_page: Map.get(params, "perPage", "50") |> String.to_integer()
      ]

      messages = Groups.list_group_messages(group_id, opts)
      json(conn, messages)
    end
  end

  @doc """
  Delete a message.
  DELETE /api/v1/groups/:group_id/messages/:message_id
  """
  def delete_message(conn, %{"group_id" => _group_id, "message_id" => message_id}) do
    user_id = conn.assigns[:current_user_id]

    case Groups.delete_message(message_id, user_id) do
      {:ok, _message} ->
        json(conn, %{message: "Message deleted"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You don't have permission to delete this message"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to delete message"})
    end
  end

  @doc """
  Search for groups.
  GET /api/v1/groups/search?q=query
  """
  def search(conn, %{"q" => query} = params) do
    opts = [
      page: Map.get(params, "page", "1") |> String.to_integer(),
      per_page: Map.get(params, "perPage", "20") |> String.to_integer()
    ]

    groups = Groups.search_groups(query, opts)
    json(conn, groups)
  end

  @doc """
  Subscribe to a public group.
  POST /api/v1/groups/:id/subscribe
  """
  def subscribe(conn, %{"id" => group_id}) do
    user_id = conn.assigns[:current_user_id]

    case Groups.subscribe_to_group(group_id, user_id) do
      {:ok, _member} ->
        json(conn, %{message: "Successfully subscribed to group"})

      {:error, :not_public_group} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Can only subscribe to public groups"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to subscribe", details: translate_errors(changeset)})
    end
  end

  @doc """
  Unsubscribe from a public group.
  DELETE /api/v1/groups/:id/subscribe
  """
  def unsubscribe(conn, %{"id" => group_id}) do
    user_id = conn.assigns[:current_user_id]

    case Groups.unsubscribe_from_group(group_id, user_id) do
      {:ok, _member} ->
        json(conn, %{message: "Successfully unsubscribed from group"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "You are not subscribed to this group"})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to unsubscribe"})
    end
  end

  # Helper function to translate changeset errors
  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
