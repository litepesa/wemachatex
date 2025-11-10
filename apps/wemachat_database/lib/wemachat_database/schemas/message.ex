defmodule WemachatDatabase.Schemas.Message do
  @moduledoc """
  Schema for chat messages.
  Messages can contain text, media (image/video/audio), or both.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.Chat

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           except: [:__meta__, :chat]}

  @media_types ["image", "video", "audio", "file"]

  schema "messages" do
    field :sender_id, :string
    field :message_text, :string
    field :media_url, :string
    field :media_type, :string
    field :is_delivered, :boolean, default: false
    field :delivered_at, :utc_datetime_usec
    field :is_read, :boolean, default: false
    field :read_at, :utc_datetime_usec
    field :is_deleted, :boolean, default: false

    belongs_to :chat, Chat, foreign_key: :chat_id, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a message.
  """
  def create_changeset(message, attrs) do
    message
    |> cast(attrs, [:chat_id, :sender_id, :message_text, :media_url, :media_type])
    |> validate_required([:chat_id, :sender_id])
    |> validate_message_content()
    |> validate_media_type()
    |> foreign_key_constraint(:chat_id)
    |> foreign_key_constraint(:sender_id)
  end

  @doc """
  Changeset for marking message as delivered.
  """
  def mark_delivered_changeset(message) do
    message
    |> change(is_delivered: true, delivered_at: DateTime.utc_now())
  end

  @doc """
  Changeset for marking message as read.
  """
  def mark_read_changeset(message) do
    message
    |> change(
      is_read: true,
      read_at: DateTime.utc_now(),
      is_delivered: true,
      delivered_at: message.delivered_at || DateTime.utc_now()
    )
  end

  @doc """
  Changeset for soft-deleting a message.
  """
  def delete_changeset(message) do
    message
    |> change(is_deleted: true)
  end

  @doc """
  Changeset for updating message content (edit).
  """
  def update_changeset(message, attrs) do
    message
    |> cast(attrs, [:message_text, :media_url, :media_type])
    |> validate_message_content()
    |> validate_media_type()
  end

  ## Private Functions

  defp validate_message_content(changeset) do
    message_text = get_field(changeset, :message_text)
    media_url = get_field(changeset, :media_url)

    if is_nil(message_text) and is_nil(media_url) do
      add_error(changeset, :message_text, "message must have text or media")
    else
      changeset
    end
  end

  defp validate_media_type(changeset) do
    media_url = get_field(changeset, :media_url)
    media_type = get_field(changeset, :media_type)

    cond do
      # If there's media, type is required
      media_url && is_nil(media_type) ->
        add_error(changeset, :media_type, "is required when media_url is present")

      # If there's a type, it must be valid
      media_type && media_type not in @media_types ->
        add_error(changeset, :media_type, "must be one of: #{Enum.join(@media_types, ", ")}")

      true ->
        changeset
    end
  end
end
