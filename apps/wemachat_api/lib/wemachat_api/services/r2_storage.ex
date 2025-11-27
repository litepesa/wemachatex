defmodule WemachatApi.Services.R2Storage do
  @moduledoc """
  Service module for Cloudflare R2 storage operations.
  Provides file upload, delete, and URL generation for R2 bucket.
  """

  alias ExAws.S3

  @doc """
  Upload a file to R2 storage.

  ## Parameters
    - key: The object key/path in the bucket (e.g., "videos/user123/video.mp4")
    - file_binary: The file content as binary
    - content_type: MIME type of the file (e.g., "video/mp4", "image/jpeg")

  ## Returns
    - `{:ok, public_url}` on success
    - `{:error, reason}` on failure
  """
  def upload_file(key, file_binary, content_type) when is_binary(file_binary) do
    bucket_name = get_bucket_name()

    case S3.put_object(bucket_name, key, file_binary,
           content_type: content_type,
           acl: :public_read
         )
         |> ExAws.request() do
      {:ok, _response} ->
        public_url = get_public_url(key)
        {:ok, public_url}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Upload a file from a file path.
  """
  def upload_file_from_path(key, file_path, content_type) do
    case File.read(file_path) do
      {:ok, file_binary} ->
        upload_file(key, file_binary, content_type)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Delete a file from R2 storage.
  """
  def delete_file(key) do
    bucket_name = get_bucket_name()

    case S3.delete_object(bucket_name, key) |> ExAws.request() do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a file exists in R2 storage.
  """
  def file_exists?(key) do
    bucket_name = get_bucket_name()

    case S3.head_object(bucket_name, key) |> ExAws.request() do
      {:ok, _response} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get the public URL for a file in R2 storage.
  """
  def get_public_url(key) do
    public_url = Application.get_env(:wemachat_api, :r2)[:public_url]
    "#{public_url}/#{key}"
  end

  @doc """
  Generate a unique filename with timestamp.
  """
  def generate_unique_filename(original_filename) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)

    extension = Path.extname(original_filename)
    base_name = Path.basename(original_filename, extension)

    "#{base_name}_#{timestamp}_#{random}#{extension}"
  end

  @doc """
  Generate a storage key for a file.

  ## Parameters
    - type: File type ("video", "thumbnail", "profile", "post", "marketplace", etc.)
    - user_id: User ID
    - filename: Filename

  ## Returns
    - Storage key (e.g., "videos/user123/filename.mp4", "marketplace/user123/filename.mp4")
  """
  def generate_key(type, user_id, filename) when type in ["video", "thumbnail", "profile", "post", "comment", "marketplace"] do
    case type do
      "video" -> "videos/#{user_id}/#{filename}"
      "thumbnail" -> "thumbnails/#{user_id}/#{filename}"
      "profile" -> "profiles/#{user_id}/#{filename}"
      "post" -> "posts/#{user_id}/#{filename}"
      "comment" -> "comments/#{user_id}/#{filename}"
      "marketplace" -> "marketplace/#{user_id}/#{filename}"
      _ -> "uploads/#{user_id}/#{filename}"
    end
  end

  ## Private Functions

  defp get_bucket_name do
    Application.get_env(:wemachat_api, :r2)[:bucket_name]
  end
end
