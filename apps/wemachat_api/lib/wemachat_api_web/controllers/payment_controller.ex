defmodule WemachatApiWeb.PaymentController do
  @moduledoc """
  Payment controller for M-Pesa STK Push payments.
  Handles both:
  1. One-time KES 99 activation payment
  2. Wallet top-up transactions
  """

  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.Payments
  alias WemachatApiWeb.Plugs.FirebaseAuth

  require Logger

  # Apply Firebase auth to all routes except callback (M-Pesa webhook)
  plug FirebaseAuth when action not in [:callback]

  @doc """
  POST /api/v1/payment/initiate
  Initiate STK Push payment (activation or wallet top-up).

  Body:
  {
    "phone_number": "254712345678",
    "amount": 99,  // Optional, defaults to 99 for activation
    "transaction_type": "activation" | "wallet_topup"  // Optional, defaults to "activation"
  }
  """
  def initiate(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)
    phone_number = params["phone_number"] || params["phoneNumber"]
    amount = parse_decimal(params["amount"], Decimal.new("99"))
    transaction_type = params["transaction_type"] || params["transactionType"] || "activation"

    if is_nil(phone_number) do
      conn
      |> put_status(:bad_request)
      |> json(%{
        success: false,
        error: "Phone number is required"
      })
    else
      payment_attrs = %{
        user_id: user_id,
        phone_number: phone_number,
        amount: amount,
        transaction_type: transaction_type
      }

      case Payments.initiate_payment(payment_attrs) do
        {:ok, %{transaction: transaction, stk_response: stk_response}} ->
          conn
          |> put_status(:ok)
          |> json(%{
            success: true,
            message: "Payment request sent. Please enter M-Pesa PIN on your phone",
            checkoutRequestId: transaction.checkout_request_id,
            checkout_request_id: transaction.checkout_request_id,
            transactionId: transaction.id,
            transaction_id: transaction.id,
            customerMessage: stk_response.customer_message,
            customer_message: stk_response.customer_message
          })

        {:error, :user_not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{
            success: false,
            error: "User not found"
          })

        {:error, :already_paid} ->
          conn
          |> put_status(:bad_request)
          |> json(%{
            success: false,
            error: "User has already paid activation fee"
          })

        {:error, {:stk_push_rejected, message}} ->
          conn
          |> put_status(:bad_request)
          |> json(%{
            success: false,
            error: message || "Payment request rejected"
          })

        {:error, :stk_push_failed} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{
            success: false,
            error: "Failed to initiate payment. Please try again."
          })

        {:error, :transaction_creation_failed} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{
            success: false,
            error: "Failed to save transaction. Please try again."
          })

        {:error, _} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{
            success: false,
            error: "Payment initiation failed"
          })
      end
    end
  end

  @doc """
  GET /api/v1/payment/status/:checkout_request_id
  Check payment status and query M-Pesa if still pending.
  """
  def status(conn, %{"checkout_request_id" => checkout_request_id}) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Payments.get_transaction_by_checkout_id(checkout_request_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{
          success: false,
          error: "Transaction not found"
        })

      transaction ->
        # Verify transaction belongs to user
        if transaction.user_id != user_id do
          conn
          |> put_status(:forbidden)
          |> json(%{
            success: false,
            error: "Access denied"
          })
        else
          # If pending, query M-Pesa for latest status
          transaction =
            if transaction.status == "pending" do
              case Payments.query_transaction_status(checkout_request_id) do
                {:ok, updated_transaction} -> updated_transaction
                _ -> transaction
              end
            else
              transaction
            end

          # Check user payment status
          has_paid = Payments.user_has_paid?(user_id)

          conn
          |> put_status(:ok)
          |> json(%{
            success: true,
            status: transaction.status,
            message: get_status_message(transaction.status),
            transaction: format_transaction(transaction),
            userHasPaid: has_paid,
            user_has_paid: has_paid
          })
        end
    end
  end

  def status(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      success: false,
      error: "checkout_request_id is required"
    })
  end

  @doc """
  POST /api/v1/payment/callback
  M-Pesa callback endpoint (webhook).
  No authentication required - called by Safaricom servers.
  """
  def callback(conn, params) do
    Logger.info("M-Pesa callback received: #{inspect(params)}")

    case Payments.parse_callback_and_update(params) do
      {:ok, transaction} ->
        Logger.info("Payment callback processed successfully for transaction: #{transaction.id}")

        conn
        |> put_status(:ok)
        |> json(%{
          ResultCode: 0,
          ResultDesc: "Accepted"
        })

      {:error, reason} ->
        Logger.error("Failed to process payment callback: #{inspect(reason)}")

        # Still return success to M-Pesa to prevent retries
        conn
        |> put_status(:ok)
        |> json(%{
          ResultCode: 0,
          ResultDesc: "Accepted"
        })
    end
  end

  @doc """
  GET /api/v1/payment/user-info
  Get current user's payment information.
  """
  def user_info(conn, _params) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Payments.get_user_payment_info(user_id) do
      {:ok, payment_info} ->
        conn
        |> put_status(:ok)
        |> json(%{
          success: true,
          data: format_payment_info(payment_info)
        })

      {:error, :user_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          success: false,
          error: "User not found"
        })

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "Failed to get payment information"
        })
    end
  end

  @doc """
  GET /api/v1/payment/transactions
  Get current user's M-Pesa transaction history.
  """
  def transactions(conn, _params) do
    user_id = FirebaseAuth.current_user_id(conn)
    transactions = Payments.get_user_transactions(user_id)

    conn
    |> put_status(:ok)
    |> json(%{
      success: true,
      transactions: Enum.map(transactions, &format_transaction/1)
    })
  end

  ## Private Functions

  defp format_transaction(transaction) do
    %{
      id: transaction.id,
      userId: transaction.user_id,
      user_id: transaction.user_id,
      phoneNumber: transaction.phone_number,
      phone_number: transaction.phone_number,
      amount: transaction.amount,
      merchantRequestId: transaction.merchant_request_id,
      merchant_request_id: transaction.merchant_request_id,
      checkoutRequestId: transaction.checkout_request_id,
      checkout_request_id: transaction.checkout_request_id,
      mpesaReceiptNumber: transaction.mpesa_receipt_number,
      mpesa_receipt_number: transaction.mpesa_receipt_number,
      transactionDate: transaction.transaction_date,
      transaction_date: transaction.transaction_date,
      resultCode: transaction.result_code,
      result_code: transaction.result_code,
      resultDesc: transaction.result_desc,
      result_desc: transaction.result_desc,
      status: transaction.status,
      initiatedAt: transaction.initiated_at,
      initiated_at: transaction.initiated_at,
      completedAt: transaction.completed_at,
      completed_at: transaction.completed_at,
      metadata: transaction.metadata,
      createdAt: transaction.inserted_at,
      created_at: transaction.inserted_at,
      updatedAt: transaction.updated_at,
      updated_at: transaction.updated_at
    }
  end

  defp format_payment_info(payment_info) do
    %{
      hasPaid: payment_info.has_paid,
      has_paid: payment_info.has_paid,
      paymentDate: payment_info.payment_date,
      payment_date: payment_info.payment_date,
      mpesaTransactionId: payment_info.mpesa_transaction_id,
      mpesa_transaction_id: payment_info.mpesa_transaction_id,
      paymentAmount: payment_info.payment_amount,
      payment_amount: payment_info.payment_amount,
      paymentPhoneNumber: payment_info.payment_phone_number,
      payment_phone_number: payment_info.payment_phone_number
    }
  end

  defp get_status_message(status) do
    case status do
      "pending" -> "Payment request sent. Waiting for user to complete payment"
      "completed" -> "Payment completed successfully"
      "failed" -> "Payment failed"
      "cancelled" -> "Payment cancelled by user"
      "timeout" -> "Payment request timed out"
      _ -> "Unknown status"
    end
  end

  defp parse_decimal(value, default) when is_binary(value) do
    case Decimal.parse(value) do
      {:ok, decimal} -> decimal
      :error -> default
    end
  end

  defp parse_decimal(value, _default) when is_number(value), do: Decimal.new(to_string(value))
  defp parse_decimal(%Decimal{} = value, _default), do: value
  defp parse_decimal(_, default), do: default
end
