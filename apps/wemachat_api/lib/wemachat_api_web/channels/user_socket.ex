defmodule WemachatApiWeb.UserSocket do
  use Phoenix.Socket

  # Channels
  channel "chat:*", WemachatApiWeb.ChatChannel
  channel "call:*", WemachatApiWeb.CallChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    # Verify Firebase token and extract user ID
    case verify_token(token) do
      {:ok, user_id} ->
        {:ok, assign(socket, :user_id, user_id)}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info) do
    :error
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"

  ## Private Functions

  defp verify_token(token) do
    # Simple JWT decode (same as FirebaseAuth plug)
    # In production, use proper Firebase Admin SDK verification
    case String.split(token, ".") do
      [_header, payload, _signature] ->
        with {:ok, decoded} <- Base.url_decode64(payload, padding: false),
             {:ok, claims} <- Jason.decode(decoded),
             user_id when is_binary(user_id) <- claims["user_id"] || claims["sub"] do
          {:ok, user_id}
        else
          _ -> {:error, :invalid_token}
        end

      _ ->
        {:error, :invalid_token}
    end
  end
end
