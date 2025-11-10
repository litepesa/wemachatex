defmodule WemachatApiWeb.Plugs.RequirePayment do
  @moduledoc """
  Plug to ensure user has paid the KES 99 activation fee before accessing protected resources.

  This plug should be applied AFTER FirebaseAuth plug, as it depends on the current_user_id being set.

  Usage in controllers:
    plug WemachatApiWeb.Plugs.FirebaseAuth
    plug WemachatApiWeb.Plugs.RequirePayment when action in [:create, :update, :delete]

  Or in router pipelines:
    pipeline :paid_users do
      plug :accepts, ["json"]
      plug WemachatApiWeb.Plugs.FirebaseAuth
      plug WemachatApiWeb.Plugs.RequirePayment
    end

  This plug can be bypassed for specific routes by using:
    plug WemachatApiWeb.Plugs.RequirePayment when action not in [:index, :show]
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias WemachatCore.Contexts.Payments
  alias WemachatApiWeb.Plugs.FirebaseAuth

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    # Get user ID from FirebaseAuth assigns
    user_id = FirebaseAuth.current_user_id(conn)

    if is_nil(user_id) do
      # FirebaseAuth plug should have caught this, but just in case
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Unauthorized - user not authenticated"})
      |> halt()
    else
      # Check if user has paid
      case Payments.user_has_paid?(user_id) do
        true ->
          # User has paid, allow request to continue
          conn

        false ->
          # User has not paid, block access
          Logger.info("Payment required for user #{user_id}")

          conn
          |> put_status(:payment_required)
          |> json(%{
            error: "Payment required",
            message: "Please complete the KES 99 activation payment to access this feature",
            has_paid: false,
            payment_url: "/api/v1/payment/initiate"
          })
          |> halt()
      end
    end
  rescue
    error ->
      Logger.error("Error checking payment status: #{inspect(error)}")

      conn
      |> put_status(:internal_server_error)
      |> json(%{error: "Failed to verify payment status"})
      |> halt()
  end
end
