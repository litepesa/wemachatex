defmodule WemachatApiWeb.UploadController do
  use WemachatApiWeb, :controller

  alias WemachatApi.Services.R2Storage
  alias WemachatApiWeb.Plugs.FirebaseAuth

  # Apply Firebase auth to all routes
  plug FirebaseAuth

  @doc """
  POST /api/v1/upload
  Upload a file to R2 storage.

  Accepts multipart form data with:
  - file: The file to upload
  - type: File type ("video", "thumbnail", "profile", "post", "comment", "marketplace", "channel_avatar", "status", "moment")
  """
  def create(conn, %{"file" => file, "type" => type}) when type in [
    "video", "thumbnail", "profile", "post", "comment",
    "marketplace", "channel_avatar", "status", "moment"
  ] do
    user_id = FirebaseAuth.current_user_id(conn)

    with {:ok, file_path} <- save_upload(file),
         {:ok, file_binary} <- File.read(file_path),
         unique_filename <- R2Storage.generate_unique_filename(file.filename),
         storage_key <- R2Storage.generate_key(type, user_id, unique_filename),
         content_type <- get_content_type(file),
         {:ok, public_url} <- R2Storage.upload_file(storage_key, file_binary, content_type) do
      # Clean up temporary file
      File.rm(file_path)

      conn
      |> put_status(:ok)
      |> json(%{
        success: true,
        url: public_url,
        key: storage_key,
        filename: unique_filename,
        contentType: content_type,
        content_type: content_type
      })
    else
      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Upload failed", reason: inspect(reason)})
    end
  end

  def create(conn, %{"file" => _file}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: type (video, thumbnail, profile, post, comment, marketplace, channel_avatar, status, moment)"})
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameters: file, type"})
  end

  @doc """
  POST /api/v1/upload/multiple
  Upload multiple files to R2 storage.

  Accepts multipart form data with:
  - files[]: Array of files to upload
  - type: File type for all files
  """
  def create_multiple(conn, %{"files" => files, "type" => type}) when is_list(files) and type in [
    "video", "thumbnail", "profile", "post", "comment",
    "marketplace", "channel_avatar", "status", "moment"
  ] do
    user_id = FirebaseAuth.current_user_id(conn)

    results =
      Enum.map(files, fn file ->
        with {:ok, file_path} <- save_upload(file),
             {:ok, file_binary} <- File.read(file_path),
             unique_filename <- R2Storage.generate_unique_filename(file.filename),
             storage_key <- R2Storage.generate_key(type, user_id, unique_filename),
             content_type <- get_content_type(file),
             {:ok, public_url} <- R2Storage.upload_file(storage_key, file_binary, content_type) do
          # Clean up temporary file
          File.rm(file_path)

          {:ok, %{
            success: true,
            url: public_url,
            key: storage_key,
            filename: unique_filename,
            contentType: content_type,
            content_type: content_type
          }}
        else
          {:error, reason} ->
            {:error, inspect(reason)}
        end
      end)

    # Separate successful and failed uploads
    {successful, failed} =
      Enum.reduce(results, {[], []}, fn
        {:ok, result}, {succ, fail} -> {[result | succ], fail}
        {:error, reason}, {succ, fail} -> {succ, [reason | fail]}
      end)

    conn
    |> put_status(:ok)
    |> json(%{
      successful: Enum.reverse(successful),
      failed: Enum.reverse(failed),
      total: length(files),
      success_count: length(successful),
      fail_count: length(failed)
    })
  end

  def create_multiple(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameters: files[], type"})
  end

  @doc """
  DELETE /api/v1/upload
  Delete a file from R2 storage.

  Accepts JSON:
  - key: The storage key of the file to delete
  """
  def delete(conn, %{"key" => key}) do
    case R2Storage.delete_file(key) do
      :ok ->
        conn
        |> put_status(:ok)
        |> json(%{message: "File deleted successfully", key: key})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Delete failed", reason: inspect(reason)})
    end
  end

  def delete(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: key"})
  end

  ## Private Functions

  defp save_upload(%Plug.Upload{path: temp_path, filename: filename}) do
    # The file is already saved to a temporary location by Plug.Upload
    {:ok, temp_path}
  end

  defp save_upload(_), do: {:error, :invalid_upload}

  defp get_content_type(%Plug.Upload{content_type: content_type}) when is_binary(content_type) do
    content_type
  end

  defp get_content_type(%Plug.Upload{filename: filename}) do
    # Fallback: guess content type from extension
    case Path.extname(filename) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".mp4" -> "video/mp4"
      ".mov" -> "video/quicktime"
      ".avi" -> "video/x-msvideo"
      ".webm" -> "video/webm"
      ".pdf" -> "application/pdf"
      _ -> "application/octet-stream"
    end
  end

  defp get_content_type(_), do: "application/octet-stream"
end
