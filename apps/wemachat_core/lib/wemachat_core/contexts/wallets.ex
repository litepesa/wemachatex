defmodule WemachatCore.Contexts.Wallets do
  @moduledoc """
  The Wallets context.
  Handles all business logic for virtual coin wallets and transactions.
  """

  import Ecto.Query, warn: false
  alias WemachatDatabase.Repo
  alias WemachatDatabase.Schemas.{Wallet, Transaction}

  ## WALLETS

  @doc """
  Get or create a wallet for a user.
  """
  def get_or_create_wallet(user_id) do
    case Repo.get_by(Wallet, user_id: user_id) do
      nil ->
        %Wallet{}
        |> Wallet.create_changeset(%{user_id: user_id})
        |> Repo.insert()

      wallet ->
        {:ok, wallet}
    end
  end

  @doc """
  Get wallet by user ID.
  """
  def get_wallet_by_user(user_id) do
    Repo.get_by(Wallet, user_id: user_id)
  end

  @doc """
  Get wallet by ID.
  """
  def get_wallet(id), do: Repo.get(Wallet, id)

  ## TRANSACTIONS - CORE OPERATIONS

  @doc """
  Add coins to a wallet (earn, purchase, admin credit, gift received).
  Creates a transaction record and updates wallet balance.
  """
  def credit_wallet(user_id, amount, transaction_type, attrs \\ %{})
      when transaction_type in ["earn", "purchase", "admin_credit", "gift_received"] do
    {:ok, wallet} = get_or_create_wallet(user_id)

    Repo.transaction(fn ->
      # Lock wallet for update
      wallet = Repo.get!(Wallet, wallet.id, lock: "FOR UPDATE")

      balance_before = wallet.balance
      balance_after = balance_before + amount

      # Create transaction record
      transaction_attrs =
        attrs
        |> Map.merge(%{
          "wallet_id" => wallet.id,
          "transaction_type" => transaction_type,
          "amount" => amount,
          "balance_before" => balance_before,
          "balance_after" => balance_after,
          "status" => "completed"
        })

      transaction =
        %Transaction{}
        |> Transaction.create_changeset(transaction_attrs)
        |> Repo.insert!()

      # Update wallet
      updated_wallet =
        wallet
        |> Wallet.update_changeset(%{
          balance: balance_after,
          total_earned: wallet.total_earned + amount
        })
        |> Repo.update!()

      {updated_wallet, transaction}
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deduct coins from a wallet (spend, gift sent, admin debit).
  Creates a transaction record and updates wallet balance.
  Returns error if insufficient balance.
  """
  def debit_wallet(user_id, amount, transaction_type, attrs \\ %{})
      when transaction_type in ["spend", "gift_sent", "admin_debit"] do
    wallet = get_wallet_by_user(user_id)

    if is_nil(wallet) do
      {:error, :wallet_not_found}
    else
      if wallet.balance < amount do
        {:error, :insufficient_balance}
      else
        Repo.transaction(fn ->
          # Lock wallet for update
          wallet = Repo.get!(Wallet, wallet.id, lock: "FOR UPDATE")

          balance_before = wallet.balance
          balance_after = balance_before - amount

          # Create transaction record
          transaction_attrs =
            attrs
            |> Map.merge(%{
              "wallet_id" => wallet.id,
              "transaction_type" => transaction_type,
              "amount" => amount,
              "balance_before" => balance_before,
              "balance_after" => balance_after,
              "status" => "completed"
            })

          transaction =
            %Transaction{}
            |> Transaction.create_changeset(transaction_attrs)
            |> Repo.insert!()

          # Update wallet
          updated_wallet =
            wallet
            |> Wallet.update_changeset(%{
              balance: balance_after,
              total_spent: wallet.total_spent + amount
            })
            |> Repo.update!()

          {updated_wallet, transaction}
        end)
        |> case do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  @doc """
  Transfer coins from one user to another (gift).
  Creates two transactions: gift_sent and gift_received.
  """
  def transfer_coins(from_user_id, to_user_id, amount, attrs \\ %{}) do
    if from_user_id == to_user_id do
      {:error, :cannot_transfer_to_self}
    else
      Repo.transaction(fn ->
        # Deduct from sender
        {:ok, {sender_wallet, sent_transaction}} =
          debit_wallet(from_user_id, amount, "gift_sent", %{
            "to_user_id" => to_user_id,
            "description" => attrs["description"] || "Gift sent",
            "metadata" => attrs["metadata"]
          })

        # Add to receiver
        {:ok, {receiver_wallet, received_transaction}} =
          credit_wallet(to_user_id, amount, "gift_received", %{
            "from_user_id" => from_user_id,
            "description" => attrs["description"] || "Gift received",
            "metadata" => attrs["metadata"]
          })

        %{
          sender_wallet: sender_wallet,
          receiver_wallet: receiver_wallet,
          sent_transaction: sent_transaction,
          received_transaction: received_transaction
        }
      end)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  ## TRANSACTION HISTORY

  @doc """
  Get transaction history for a wallet.
  """
  def list_wallet_transactions(wallet_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    Transaction
    |> where([t], t.wallet_id == ^wallet_id)
    |> order_by([t], desc: t.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Get transaction history for a user (by user_id).
  """
  def list_user_transactions(user_id, opts \\ []) do
    case get_wallet_by_user(user_id) do
      nil -> []
      wallet -> list_wallet_transactions(wallet.id, opts)
    end
  end

  @doc """
  Get a single transaction by ID.
  """
  def get_transaction(id), do: Repo.get(Transaction, id)

  ## STATISTICS

  @doc """
  Get total coins in circulation (sum of all wallet balances).
  """
  def total_coins_in_circulation do
    Wallet
    |> where([w], w.is_active == true)
    |> select([w], sum(w.balance))
    |> Repo.one() || 0
  end

  @doc """
  Get total coins earned across all users.
  """
  def total_coins_earned do
    Wallet
    |> where([w], w.is_active == true)
    |> select([w], sum(w.total_earned))
    |> Repo.one() || 0
  end

  @doc """
  Get total coins spent across all users.
  """
  def total_coins_spent do
    Wallet
    |> where([w], w.is_active == true)
    |> select([w], sum(w.total_spent))
    |> Repo.one() || 0
  end

  @doc """
  Count total transactions.
  """
  def count_transactions do
    Transaction
    |> where([t], t.status == "completed")
    |> Repo.aggregate(:count)
  end

  @doc """
  Get transaction summary by type.
  """
  def transaction_summary_by_type do
    Transaction
    |> where([t], t.status == "completed")
    |> group_by([t], t.transaction_type)
    |> select([t], {t.transaction_type, count(t.id), sum(t.amount)})
    |> Repo.all()
    |> Enum.map(fn {type, count, total} ->
      %{type: type, count: count, total_amount: total || 0}
    end)
  end
end
