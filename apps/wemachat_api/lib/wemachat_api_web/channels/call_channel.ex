defmodule WemachatApiWeb.CallChannel do
  @moduledoc """
  Phoenix Channel for WebRTC call signaling.
  Handles peer-to-peer connection establishment between two users.

  Events:
  - call:initiate - Start a new call
  - call:offer - Send WebRTC offer (SDP)
  - call:answer - Send WebRTC answer (SDP)
  - call:ice_candidate - Send ICE candidate for NAT traversal
  - call:accept - Accept incoming call
  - call:reject - Reject incoming call
  - call:cancel - Cancel outgoing call
  - call:end - End active call
  """
  use WemachatApiWeb, :channel

  alias WemachatCore.Contexts.Calls
  alias WemachatDatabase.Schemas.Call

  ## JOIN

  @doc """
  Join user's personal call channel.
  Topic: "call:user_id"
  This allows receiving incoming call notifications.
  """
  def join("call:" <> user_id, _payload, socket) do
    if socket.assigns.user_id == user_id do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  ## INCOMING EVENTS (from client)

  @doc """
  Initiate a new call.
  """
  def handle_in("call:initiate", %{"callee_id" => callee_id, "call_type" => call_type}, socket) do
    caller_id = socket.assigns.user_id

    case Calls.initiate_call(caller_id, callee_id, call_type) do
      {:ok, call} ->
        # Notify callee about incoming call
        broadcast_to_user(callee_id, "call:incoming", %{
          call_id: call.id,
          caller_id: caller_id,
          call_type: call_type,
          timestamp: DateTime.to_iso8601(call.inserted_at)
        })

        # Update call to ringing status
        Calls.mark_call_ringing(call.id)

        {:reply, {:ok, %{call_id: call.id, status: "ringing"}}, socket}

      {:error, changeset} ->
        {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
    end
  end

  @doc """
  Send WebRTC offer to callee.
  """
  def handle_in("call:offer", %{"call_id" => call_id, "sdp" => sdp}, socket) do
    case get_and_verify_call(call_id, socket.assigns.user_id) do
      {:ok, call} ->
        other_user_id = Call.other_user_id(call, socket.assigns.user_id)

        broadcast_to_user(other_user_id, "call:offer_received", %{
          call_id: call_id,
          caller_id: socket.assigns.user_id,
          sdp: sdp
        })

        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @doc """
  Send WebRTC answer to caller.
  """
  def handle_in("call:answer", %{"call_id" => call_id, "sdp" => sdp}, socket) do
    case get_and_verify_call(call_id, socket.assigns.user_id) do
      {:ok, call} ->
        other_user_id = Call.other_user_id(call, socket.assigns.user_id)

        broadcast_to_user(other_user_id, "call:answer_received", %{
          call_id: call_id,
          callee_id: socket.assigns.user_id,
          sdp: sdp
        })

        # Mark call as active
        Calls.start_call(call_id)

        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @doc """
  Send ICE candidate to the other peer.
  """
  def handle_in("call:ice_candidate", %{"call_id" => call_id, "candidate" => candidate}, socket) do
    case get_and_verify_call(call_id, socket.assigns.user_id) do
      {:ok, call} ->
        other_user_id = Call.other_user_id(call, socket.assigns.user_id)

        broadcast_to_user(other_user_id, "call:ice_candidate_received", %{
          call_id: call_id,
          from_user_id: socket.assigns.user_id,
          candidate: candidate
        })

        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @doc """
  Accept an incoming call.
  """
  def handle_in("call:accept", %{"call_id" => call_id}, socket) do
    case get_and_verify_call(call_id, socket.assigns.user_id) do
      {:ok, call} ->
        # Notify caller that call was accepted
        broadcast_to_user(call.caller_id, "call:accepted", %{
          call_id: call_id,
          callee_id: socket.assigns.user_id
        })

        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @doc """
  Reject an incoming call.
  """
  def handle_in("call:reject", %{"call_id" => call_id}, socket) do
    case get_and_verify_call(call_id, socket.assigns.user_id) do
      {:ok, call} ->
        Calls.reject_call(call_id)

        # Notify caller that call was rejected
        broadcast_to_user(call.caller_id, "call:rejected", %{
          call_id: call_id,
          callee_id: socket.assigns.user_id
        })

        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @doc """
  Cancel an outgoing call (before it's answered).
  """
  def handle_in("call:cancel", %{"call_id" => call_id}, socket) do
    case get_and_verify_call(call_id, socket.assigns.user_id) do
      {:ok, call} ->
        Calls.cancel_call(call_id)

        # Notify callee that call was cancelled
        broadcast_to_user(call.callee_id, "call:cancelled", %{
          call_id: call_id,
          caller_id: socket.assigns.user_id
        })

        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @doc """
  End an active call.
  """
  def handle_in("call:end", %{"call_id" => call_id}, socket) do
    case get_and_verify_call(call_id, socket.assigns.user_id) do
      {:ok, call} ->
        Calls.end_call(call_id)

        other_user_id = Call.other_user_id(call, socket.assigns.user_id)

        # Notify other user that call ended
        broadcast_to_user(other_user_id, "call:ended", %{
          call_id: call_id,
          ended_by: socket.assigns.user_id
        })

        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  ## PRIVATE HELPERS

  defp get_and_verify_call(call_id, user_id) do
    case Calls.get_call(call_id) do
      nil ->
        {:error, "call_not_found"}

      call ->
        if Call.participant?(call, user_id) do
          {:ok, call}
        else
          {:error, "unauthorized"}
        end
    end
  end

  defp broadcast_to_user(user_id, event, payload) do
    WemachatApiWeb.Endpoint.broadcast("call:#{user_id}", event, payload)
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
