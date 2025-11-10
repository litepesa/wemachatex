defmodule WemachatCore.Contexts.Payments do
  @moduledoc """
  Payment context for M-Pesa payment operations.
  Handles both:
  1. One-time KES 99 activation payment
  2. Wallet top-up transactions
  """

  import Ecto.Query, warn: false
  alias WemachatDatabase.Repo
  alias WemachatDatabase.Schemas.{MpesaPaymentTransaction, User}
  alias WemachatCore.Services.MpesaClient
  alias WemachatCore.Contexts.Wallets

  require Logger

  @doc """
  Initiate STK Push payment for activation (KES 99) or wallet top-up.

  ## Parameters
  - attrs: Map with :user_id, :phone_number, :amount, :transaction_type
  - transaction_type: "activation" or "wallet_topup"

  ## Returns
  - {:ok, transaction} on success
  - {:error, reason} on failure
  """
  def initiate_payment(attrs) do
    user_id = attrs[:user_id] || attrs["user_id"]
    phone_number = attrs[:phone_number] || attrs["phone_number"]
    amount = attrs[:amount] || attrs["amount"] || 99
    transaction_type = attrs[:transaction_type] || attrs["transaction_type"] || "activation"

    # Validate user exists
    case get_user(user_id) do
      nil ->
        {:error, :user_not_found}

      user ->
        # For activation payments, check if user already paid
        if transaction_type == "activation" do
          if user.has_paid do
            {:error, :already_paid}
          else
            do_initiate_payment(user_id, phone_number, amount, transaction_type)
          end
        else
          # Wallet top-up - no restrictions
          do_initiate_payment(user_id, phone_number, amount, transaction_type)
        end
    end
  end

  defp do_initiate_payment(user_id, phone_number, amount, transaction_type) do
    # Format phone number (ensure 254 prefix)
    formatted_phone = format_phone_number(phone_number)

    # Generate account reference
    account_ref = generate_account_reference(user_id, transaction_type)

    # Generate transaction description
    transaction_desc = generate_transaction_description(transaction_type, amount)

    # Initiate STK Push via M-Pesa API
    case MpesaClient.initiate_stk_push(
           formatted_phone,
           amount,
           account_ref,
           transaction_desc
         ) do
      {:ok, stk_response} ->
        # Check response code (0 = success)
        if stk_response.response_code == "0" do
          # Create transaction record
          transaction_attrs = %{
            id: Ecto.UUID.generate(),
            user_id: user_id,
            phone_number: formatted_phone,
            amount: amount,
            merchant_request_id: stk_response.merchant_request_id,
            checkout_request_id: stk_response.checkout_request_id,
            status: "pending",
            initiated_at: DateTime.utc_now(),
            metadata: %{
              transaction_type: transaction_type,
              account_reference: account_ref
            }
          }

          case create_transaction(transaction_attrs) do
            {:ok, transaction} ->
              {:ok, %{transaction: transaction, stk_response: stk_response}}

            {:error, changeset} ->
              Logger.error("Failed to create transaction: #{inspect(changeset)}")
              {:error, :transaction_creation_failed}
          end
        else
          Logger.warning("STK Push rejected: #{stk_response.response_description}")
          {:error, {:stk_push_rejected, stk_response.customer_message}}
        end

      {:error, reason} ->
        Logger.error("STK Push failed: #{inspect(reason)}")
        {:error, :stk_push_failed}
    end
  end

  @doc """
  Create a new payment transaction record.
  """
  def create_transaction(attrs) do
    %MpesaPaymentTransaction{}
    |> MpesaPaymentTransaction.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Get transaction by checkout request ID.
  """
  def get_transaction_by_checkout_id(checkout_request_id) do
    Repo.get_by(MpesaPaymentTransaction, checkout_request_id: checkout_request_id)
  end

  @doc """
  Get all transactions for a user.
  """
  def get_user_transactions(user_id) do
    MpesaPaymentTransaction
    |> where([t], t.user_id == ^user_id)
    |> order_by([t], desc: t.initiated_at)
    |> Repo.all()
  end

  @doc """
  Update transaction from M-Pesa callback.

  Handles both activation payments and wallet top-ups.
  """
  def update_transaction_from_callback(checkout_request_id, callback_data) do
    transaction = get_transaction_by_checkout_id(checkout_request_id)

    if is_nil(transaction) do
      {:error, :transaction_not_found}
    else
      result_code = callback_data.result_code
      result_desc = callback_data.result_desc

      # Determine status based on result code
      status =
        case result_code do
          0 -> "completed"
          1032 -> "cancelled"
          1 -> "timeout"
          _ -> "failed"
        end

      # Prepare update attributes
      update_attrs = %{
        result_code: result_code,
        result_desc: result_desc,
        status: status,
        completed_at: DateTime.utc_now()
      }

      # Add success fields if payment completed
      update_attrs =
        if result_code == 0 do
          Map.merge(update_attrs, %{
            mpesa_receipt_number: callback_data.mpesa_receipt_number,
            transaction_date: callback_data.transaction_date || DateTime.utc_now()
          })
        else
          update_attrs
        end

      # Update transaction
      case update_transaction_status(transaction, update_attrs) do
        {:ok, updated_transaction} ->
          # If payment successful, handle post-payment actions
          if result_code == 0 do
            handle_successful_payment(updated_transaction)
          else
            {:ok, updated_transaction}
          end

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Parse M-Pesa callback data and update transaction.
  Convenience function that combines parsing and updating.
  """
  def parse_callback_and_update(callback_params) do
    case MpesaClient.parse_callback_data(callback_params) do
      {:ok, callback_data} ->
        update_transaction_from_callback(
          callback_data.checkout_request_id,
          callback_data
        )

      {:error, reason} ->
        Logger.error("Failed to parse callback data: #{inspect(reason)}")
        {:error, :invalid_callback}
    end
  end

  @doc """
  Update transaction status (from query or manual update).
  """
  def update_transaction_status(transaction, attrs) do
    transaction
    |> MpesaPaymentTransaction.callback_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Query M-Pesa for transaction status and update database.
  """
  def query_transaction_status(checkout_request_id) do
    transaction = get_transaction_by_checkout_id(checkout_request_id)

    if is_nil(transaction) do
      {:error, :transaction_not_found}
    else
      case MpesaClient.query_stk_push_status(checkout_request_id) do
        {:ok, query_response} ->
          result_code = query_response.result_code

          if result_code == "0" do
            # Payment successful
            update_attrs = %{
              status: "completed",
              result_code: 0,
              result_desc: query_response.result_desc,
              completed_at: DateTime.utc_now()
            }

            case update_transaction_status(transaction, update_attrs) do
              {:ok, updated_transaction} ->
                handle_successful_payment(updated_transaction)

              {:error, changeset} ->
                {:error, changeset}
            end
          else
            # Payment failed or still pending
            {:ok, transaction}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Check if user has paid activation fee.
  """
  def user_has_paid?(user_id) do
    case get_user(user_id) do
      nil -> false
      user -> user.has_paid
    end
  end

  @doc """
  Get user payment info.
  """
  def get_user_payment_info(user_id) do
    user = get_user(user_id)

    if is_nil(user) do
      {:error, :user_not_found}
    else
      {:ok,
       %{
         has_paid: user.has_paid,
         payment_date: user.payment_date,
         mpesa_transaction_id: user.mpesa_transaction_id,
         payment_amount: user.payment_amount,
         payment_phone_number: user.payment_phone_number
       }}
    end
  end

  # Private Functions

  defp handle_successful_payment(transaction) do
    transaction_type = get_in(transaction.metadata, ["transaction_type"])

    case transaction_type do
      "activation" ->
        # Mark user as paid
        mark_user_as_paid(
          transaction.user_id,
          transaction.mpesa_receipt_number,
          transaction.amount,
          transaction.phone_number
        )

      "wallet_topup" ->
        # Add coins to user wallet
        add_coins_to_wallet(transaction)

      _ ->
        {:ok, transaction}
    end
  end

  defp mark_user_as_paid(user_id, mpesa_receipt_number, amount, phone_number) do
    user = get_user(user_id)

    if is_nil(user) do
      {:error, :user_not_found}
    else
      user
      |> Ecto.Changeset.change(%{
        has_paid: true,
        payment_date: DateTime.utc_now(),
        mpesa_transaction_id: mpesa_receipt_number,
        payment_amount: amount,
        payment_phone_number: phone_number
      })
      |> Repo.update()
    end
  end

  defp add_coins_to_wallet(transaction) do
    # Calculate coins based on amount (e.g., KES 10 = 10 coins, KES 100 = 100 coins)
    coins_to_add = Decimal.to_integer(transaction.amount)

    case Wallets.credit_wallet(transaction.user_id, coins_to_add, "purchase", %{
           "description" => "M-Pesa wallet top-up",
           "metadata" => %{
             mpesa_receipt_number: transaction.mpesa_receipt_number,
             transaction_id: transaction.id
           }
         }) do
      {:ok, {wallet, _wallet_transaction}} ->
        Logger.info(
          "Added #{coins_to_add} coins to wallet for user #{transaction.user_id}: #{transaction.mpesa_receipt_number}"
        )

        {:ok, %{transaction: transaction, wallet: wallet}}

      {:error, reason} ->
        Logger.error(
          "Failed to add coins to wallet for user #{transaction.user_id}: #{inspect(reason)}"
        )

        {:error, :wallet_update_failed}
    end
  end

  defp get_user(user_id) do
    Repo.get(User, user_id)
  end

  defp format_phone_number(phone_number) when is_binary(phone_number) do
    # Remove any non-digit characters
    digits = String.replace(phone_number, ~r/\D/, "")

    # Add 254 prefix if not present
    cond do
      String.starts_with?(digits, "254") -> digits
      String.starts_with?(digits, "0") -> "254" <> String.slice(digits, 1..-1)
      String.starts_with?(digits, "7") -> "254" <> digits
      true -> digits
    end
  end

  defp format_phone_number(phone_number), do: to_string(phone_number)

  defp generate_account_reference(user_id, transaction_type) do
    user_prefix = String.slice(user_id, 0..7)

    case transaction_type do
      "activation" -> "WEMA_ACT_#{user_prefix}"
      "wallet_topup" -> "WEMA_TOP_#{user_prefix}"
      _ -> "WEMA_#{user_prefix}"
    end
  end

  defp generate_transaction_description(transaction_type, amount) do
    case transaction_type do
      "activation" -> "WemaChat Activation Fee"
      "wallet_topup" -> "WemaChat Wallet Top-up KES #{amount}"
      _ -> "WemaChat Payment"
    end
  end
end
