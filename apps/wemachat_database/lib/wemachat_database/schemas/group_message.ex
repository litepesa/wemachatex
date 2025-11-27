defmodule WemachatDatabase.Schemas.GroupMessage do
  @moduledoc """
  Schema for messages in group chats.
  Supports text, media attachments, and read receipts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.Group

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           except: [:__meta__, :group]}

  @valid_media_types ["image", "video", "audio", "document"]

  schema "group_messages" do
    field :group_id, :binary_id
    field :sender_id, :string
    field :message_text, :string
    field :media_url, :string
    field :media_type, :string
    field :is_deleted, :boolean, default: false
    field :read_by, {:array, :string}, default: []

    belongs_to :group, Group, define_field: false, references: :id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a group message.
  """
  def create_changeset(group_message, attrs) do
    group_message
    |> cast(attrs, [:group_id, :sender_id, :message_text, :media_url, :media_type])
    |> validate_required([:group_id, :sender_id])
    |> validate_message_content()
    |> validate_inclusion(:media_type, @valid_media_types)
  end

  @doc """
  Changeset for updating message (mainly for soft delete).
  """
  def update_changeset(group_message, attrs) do
    group_message
    |> cast(attrs, [:is_deleted, :read_by])
  end

  @doc """
  Mark message as read by a user.
  """
  def mark_as_read(%__MODULE__{} = message, user_id) do
    if user_id in message.read_by do
      {:ok, message}
    else
      change(message)
      |> put_change(:read_by, [user_id | message.read_by])
    end
  end

  @doc """
  Check if message has been read by a specific user.
  """
  def read_by?(%__MODULE__{read_by: read_by}, user_id) do
    user_id in read_by
  end

  @doc """
  Get list of valid media types.
  """
  def valid_media_types, do: @valid_media_types

  ## Private Functions

  defp validate_message_content(changeset) do
    message_text = get_field(changeset, :message_text)
    media_url = get_field(changeset, :media_url)

    cond do
      is_binary(message_text) and String.trim(message_text) != "" ->
        changeset

      is_binary(media_url) and String.trim(media_url) != "" ->
        changeset

      true ->
        add_error(changeset, :message_text, "Message must have either text or media")
    end
  end
end
