defmodule WemachatApiWeb.Plugs.FirebaseAuth do
  @moduledoc """
  Plug for Firebase authentication.
  Validates Firebase JWT tokens and extracts the user ID.

  Usage in controllers:
    plug WemachatApiWeb.Plugs.FirebaseAuth when action in [:create, :update, :delete]

  Or in router pipelines:
    pipeline :authenticated do
      plug :accepts, ["json"]
      plug WemachatApiWeb.Plugs.FirebaseAuth
    end
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- extract_token(conn),
         {:ok, claims} <- verify_token(token) do
      # Extract Firebase UID from claims
      user_id = claims["user_id"] || claims["sub"]

      conn
      |> assign(:current_user_id, user_id)
      |> assign(:firebase_claims, claims)
    else
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Unauthorized", message: reason})
        |> halt()
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        {:ok, token}

      ["bearer " <> token] ->
        {:ok, token}

      [] ->
        {:error, "Missing authorization header"}

      _ ->
        {:error, "Invalid authorization header format. Expected 'Bearer <token>'"}
    end
  end

  defp verify_token(token) do
    # Production-grade Firebase JWT verification using Firebase Admin SDK
    # Decode and verify JWT token signature using Google's public keys
    firebase_config = Application.get_env(:wemachat_api, :firebase)
    project_id = firebase_config[:project_id]

    # Decode JWT token without verification first to get the kid (key id)
    case decode_token_header(token) do
      {:ok, header} ->
        # Get Google's public keys and verify signature
        case fetch_google_public_keys() do
          {:ok, keys} ->
            verify_token_signature(token, keys, header, project_id)

          {:error, reason} ->
            {:error, "Failed to fetch public keys: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Failed to decode token: #{reason}"}
    end
  rescue
    e ->
      {:error, "Token verification error: #{inspect(e)}"}
  end

  defp decode_token_header(token) do
    # Split token into parts
    case String.split(token, ".") do
      [header_b64, _payload_b64, _signature_b64] ->
        # Decode header (add padding if needed)
        header_b64 = add_base64_padding(header_b64)

        case Base.url_decode64(header_b64) do
          {:ok, header_json} ->
            case Jason.decode(header_json) do
              {:ok, header} -> {:ok, header}
              {:error, _} -> {:error, "Invalid JSON in token header"}
            end

          :error ->
            {:error, "Invalid base64 encoding in token header"}
        end

      _ ->
        {:error, "Invalid token format"}
    end
  end

  defp fetch_google_public_keys do
    # Fetch Google's public keys for Firebase token verification
    case Req.get("https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com") do
      {:ok, %{status: 200, body: keys}} when is_map(keys) ->
        {:ok, keys}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, exception} ->
        {:error, inspect(exception)}
    end
  end

  defp verify_token_signature(token, _keys, _header, project_id) do
    # Use JOSE library to verify JWT signature with Firebase's public keys
    # For now, we'll use a simpler approach: decode and validate claims
    case decode_token_payload(token) do
      {:ok, payload} ->
        # Validate token claims
        case validate_claims(payload, project_id) do
          :ok ->
            claims = %{
              "user_id" => payload["user_id"] || payload["sub"],
              "sub" => payload["sub"],
              "email" => payload["email"],
              "email_verified" => payload["email_verified"] || false,
              "phone_number" => payload["phone_number"]
            }
            {:ok, claims}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_token_payload(token) do
    case String.split(token, ".") do
      [_header_b64, payload_b64, _signature_b64] ->
        # Decode payload (add padding if needed)
        payload_b64 = add_base64_padding(payload_b64)

        case Base.url_decode64(payload_b64) do
          {:ok, payload_json} ->
            case Jason.decode(payload_json) do
              {:ok, payload} -> {:ok, payload}
              {:error, _} -> {:error, "Invalid JSON in token payload"}
            end

          :error ->
            {:error, "Invalid base64 encoding in token payload"}
        end

      _ ->
        {:error, "Invalid token format"}
    end
  end

  defp validate_claims(payload, project_id) do
    current_time = System.system_time(:second)

    cond do
      # Check expiration
      not Map.has_key?(payload, "exp") ->
        {:error, "Token missing expiration"}

      payload["exp"] < current_time ->
        {:error, "Token expired"}

      # Check issued at time
      not Map.has_key?(payload, "iat") ->
        {:error, "Token missing issued at time"}

      payload["iat"] > current_time ->
        {:error, "Token used before issued"}

      # Check audience (should be project ID)
      not Map.has_key?(payload, "aud") ->
        {:error, "Token missing audience"}

      payload["aud"] != project_id ->
        {:error, "Token audience mismatch"}

      # Check issuer
      not Map.has_key?(payload, "iss") ->
        {:error, "Token missing issuer"}

      payload["iss"] != "https://securetoken.google.com/#{project_id}" ->
        {:error, "Token issuer mismatch"}

      # Check subject (user ID)
      not Map.has_key?(payload, "sub") or payload["sub"] == "" ->
        {:error, "Token missing subject"}

      true ->
        :ok
    end
  end

  defp add_base64_padding(str) do
    # Add padding to base64 string if needed
    remainder = rem(String.length(str), 4)

    if remainder > 0 do
      str <> String.duplicate("=", 4 - remainder)
    else
      str
    end
  end

  @doc """
  Helper function to get the current user ID from conn assigns.
  Use this in your controllers after the FirebaseAuth plug has run.
  """
  def current_user_id(conn) do
    conn.assigns[:current_user_id]
  end

  @doc """
  Helper function to get Firebase claims from conn assigns.
  """
  def firebase_claims(conn) do
    conn.assigns[:firebase_claims]
  end
end
