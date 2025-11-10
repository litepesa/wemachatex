defmodule WemachatApiWeb.GiftController do
  use WemachatApiWeb, :controller
  alias WemachatCore.Contexts.Gifts

  @doc """
  POST /api/gifts/send
  Send a gift from current user to another user.
  """
  def send_gift(conn, params) do
    current_user_id = conn.assigns[:current_user_id]

    if is_nil(current_user_id) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Unauthorized"})
    else
      # Add sender_id to params
      params_with_sender = Map.put(params, "senderId", current_user_id)

      case Gifts.send_gift(params_with_sender) do
        {:ok, gift_transaction} ->
          # Get updated wallet balances
          sender_wallet = WemachatCore.Contexts.Wallets.get_wallet(current_user_id)
          recipient_wallet = WemachatCore.Contexts.Wallets.get_wallet(params["recipientId"])

          conn
          |> put_status(:ok)
          |> json(%{
            success: true,
            transaction: %{
              id: gift_transaction.id,
              giftId: gift_transaction.gift_id,
              giftName: gift_transaction.gift_name,
              giftEmoji: gift_transaction.gift_emoji,
              price: gift_transaction.price,
              recipientAmount: gift_transaction.recipient_amount,
              platformCommission: gift_transaction.platform_commission
            },
            senderNewBalance: sender_wallet.balance,
            recipientNewBalance: recipient_wallet.balance
          })

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Validation error", details: translate_errors(changeset)})

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: reason})
      end
    end
  end

  @doc """
  GET /api/gifts/catalog
  Get the full gift catalog.
  """
  def get_catalog(conn, _params) do
    catalog = Gifts.get_gift_catalog()

    conn
    |> put_status(:ok)
    |> json(%{
      gifts: catalog,
      total: length(catalog),
      commissionRate: 0.20
    })
  end

  @doc """
  GET /api/gifts/history/:user_id
  Get gift history for a user.
  """
  def get_history(conn, %{"user_id" => user_id} = params) do
    limit = String.to_integer(params["limit"] || "50")
    offset = String.to_integer(params["offset"] || "0")

    history = Gifts.get_user_gift_history(user_id, limit: limit, offset: offset)

    conn
    |> put_status(:ok)
    |> json(%{
      history: Enum.map(history, &format_gift_transaction/1),
      total: length(history)
    })
  end

  @doc """
  GET /api/gifts/stats/:user_id
  Get gift statistics for a user.
  """
  def get_stats(conn, %{"user_id" => user_id}) do
    stats = Gifts.get_user_gift_stats(user_id)

    conn
    |> put_status(:ok)
    |> json(stats)
  end

  # Private helpers

  defp format_gift_transaction(transaction) do
    %{
      id: transaction.id,
      giftId: transaction.gift_id,
      giftName: transaction.gift_name,
      giftEmoji: transaction.gift_emoji,
      giftRarity: transaction.gift_rarity,
      price: transaction.price,
      recipientAmount: transaction.recipient_amount,
      platformCommission: transaction.platform_commission,
      context: transaction.context,
      contextId: transaction.context_id,
      message: transaction.message,
      senderId: transaction.sender_id,
      recipientId: transaction.recipient_id,
      insertedAt: transaction.inserted_at
    }
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
