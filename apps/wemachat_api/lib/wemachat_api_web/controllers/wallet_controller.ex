defmodule WemachatApiWeb.WalletController do
  use WemachatApiWeb, :controller

  alias WemachatCore.Contexts.Wallets
  alias WemachatApiWeb.Plugs.FirebaseAuth

  # Apply Firebase auth to all routes
  plug FirebaseAuth

  @doc """
  GET /api/v1/wallet
  Get current user's wallet.
  """
  def show(conn, _params) do
    user_id = FirebaseAuth.current_user_id(conn)

    case Wallets.get_or_create_wallet(user_id) do
      {:ok, wallet} ->
        conn
        |> put_status(:ok)
        |> json(format_wallet(wallet))

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to get wallet"})
    end
  end

  @doc """
  GET /api/v1/wallet/transactions
  Get current user's transaction history.
  """
  def transactions(conn, params) do
    user_id = FirebaseAuth.current_user_id(conn)
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 20)

    transactions = Wallets.list_user_transactions(user_id, page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      transactions: Enum.map(transactions, &format_transaction/1),
      page: page,
      per_page: per_page
    })
  end

  @doc """
  POST /api/v1/wallet/transfer
  Transfer coins to another user (send gift).
  """
  def transfer(conn, %{"to_user_id" => to_user_id, "amount" => amount} = params) do
    from_user_id = FirebaseAuth.current_user_id(conn)
    amount = parse_int(amount, 0)

    if amount <= 0 do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Amount must be greater than 0"})
    else
      attrs = %{
        "description" => params["description"] || "Gift",
        "metadata" => params["metadata"] || %{}
      }

      case Wallets.transfer_coins(from_user_id, to_user_id, amount, attrs) do
        {:ok, result} ->
          conn
          |> put_status(:ok)
          |> json(%{
            message: "Transfer successful",
            sender_wallet: format_wallet(result.sender_wallet),
            receiver_wallet: format_wallet(result.receiver_wallet)
          })

        {:error, :cannot_transfer_to_self} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Cannot transfer to yourself"})

        {:error, :wallet_not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Wallet not found"})

        {:error, :insufficient_balance} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Insufficient balance"})

        {:error, _} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Transfer failed"})
      end
    end
  end

  def transfer(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameters: to_user_id, amount"})
  end

  @doc """
  POST /api/v1/wallet/earn
  Add coins to user's wallet (for achievements, daily login, etc.).
  """
  def earn(conn, %{"amount" => amount} = params) do
    user_id = FirebaseAuth.current_user_id(conn)
    amount = parse_int(amount, 0)

    if amount <= 0 do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Amount must be greater than 0"})
    else
      attrs = %{
        "description" => params["description"] || "Earned coins",
        "related_id" => params["related_id"],
        "related_type" => params["related_type"],
        "metadata" => params["metadata"] || %{}
      }

      case Wallets.credit_wallet(user_id, amount, "earn", attrs) do
        {:ok, {wallet, transaction}} ->
          conn
          |> put_status(:ok)
          |> json(%{
            message: "Coins added successfully",
            wallet: format_wallet(wallet),
            transaction: format_transaction(transaction)
          })

        {:error, _} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to add coins"})
      end
    end
  end

  def earn(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: amount"})
  end

  @doc """
  POST /api/v1/wallet/spend
  Deduct coins from user's wallet (for unlocking content, etc.).
  """
  def spend(conn, %{"amount" => amount} = params) do
    user_id = FirebaseAuth.current_user_id(conn)
    amount = parse_int(amount, 0)

    if amount <= 0 do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Amount must be greater than 0"})
    else
      attrs = %{
        "description" => params["description"] || "Spent coins",
        "related_id" => params["related_id"],
        "related_type" => params["related_type"],
        "metadata" => params["metadata"] || %{}
      }

      case Wallets.debit_wallet(user_id, amount, "spend", attrs) do
        {:ok, {wallet, transaction}} ->
          conn
          |> put_status(:ok)
          |> json(%{
            message: "Coins spent successfully",
            wallet: format_wallet(wallet),
            transaction: format_transaction(transaction)
          })

        {:error, :wallet_not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Wallet not found"})

        {:error, :insufficient_balance} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Insufficient balance"})

        {:error, _} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to spend coins"})
      end
    end
  end

  def spend(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: amount"})
  end

  ## Private Functions

  defp format_wallet(wallet) do
    %{
      id: wallet.id,
      userId: wallet.user_id,
      user_id: wallet.user_id,
      balance: wallet.balance,
      totalEarned: wallet.total_earned,
      total_earned: wallet.total_earned,
      totalSpent: wallet.total_spent,
      total_spent: wallet.total_spent,
      isActive: wallet.is_active,
      is_active: wallet.is_active,
      createdAt: wallet.inserted_at,
      created_at: wallet.inserted_at,
      updatedAt: wallet.updated_at,
      updated_at: wallet.updated_at
    }
  end

  defp format_transaction(transaction) do
    %{
      id: transaction.id,
      walletId: transaction.wallet_id,
      wallet_id: transaction.wallet_id,
      transactionType: transaction.transaction_type,
      transaction_type: transaction.transaction_type,
      amount: transaction.amount,
      balanceBefore: transaction.balance_before,
      balance_before: transaction.balance_before,
      balanceAfter: transaction.balance_after,
      balance_after: transaction.balance_after,
      fromUserId: transaction.from_user_id,
      from_user_id: transaction.from_user_id,
      toUserId: transaction.to_user_id,
      to_user_id: transaction.to_user_id,
      relatedId: transaction.related_id,
      related_id: transaction.related_id,
      relatedType: transaction.related_type,
      related_type: transaction.related_type,
      description: transaction.description,
      metadata: transaction.metadata,
      status: transaction.status,
      createdAt: transaction.inserted_at,
      created_at: transaction.inserted_at
    }
  end

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(_, default), do: default
end
