defmodule WemachatCore.Contexts.Gifts do
  @moduledoc """
  The Gifts context.
  Handles all business logic for virtual gift transactions.
  """

  import Ecto.Query, warn: false
  alias WemachatDatabase.Repo
  alias WemachatDatabase.Schemas.GiftTransaction
  alias WemachatCore.Contexts.Wallets

  # Default platform commission rate (20%)
  @default_commission_rate 0.20

  # Gift catalog matching Flutter app and Go backend
  @gift_catalog %{
    # Popular
    "heart" => %{price: 10, name: "Heart", emoji: "❤️", rarity: "common"},
    "thumbs_up" => %{price: 15, name: "Thumbs Up", emoji: "👍", rarity: "common"},
    "clap" => %{price: 25, name: "Applause", emoji: "👏", rarity: "uncommon"},
    "fire" => %{price: 50, name: "Fire", emoji: "🔥", rarity: "rare"},
    "star" => %{price: 75, name: "Star", emoji: "⭐", rarity: "rare"},
    "crown" => %{price: 150, name: "Crown", emoji: "👑", rarity: "epic"},
    "kiss" => %{price: 35, name: "Kiss", emoji: "💋", rarity: "uncommon"},
    "muscle" => %{price: 40, name: "Strong", emoji: "💪", rarity: "uncommon"},

    # Emotions
    "love_eyes" => %{price: 20, name: "Love Eyes", emoji: "😍", rarity: "common"},
    "laugh" => %{price: 15, name: "Laughing", emoji: "😂", rarity: "common"},
    "cool" => %{price: 30, name: "Cool", emoji: "😎", rarity: "uncommon"},
    "shocked" => %{price: 25, name: "Shocked", emoji: "😱", rarity: "uncommon"},
    "party" => %{price: 40, name: "Party", emoji: "🥳", rarity: "rare"},
    "mind_blown" => %{price: 60, name: "Mind Blown", emoji: "🤯", rarity: "rare"},
    "crying_laugh" => %{price: 35, name: "Crying Laugh", emoji: "🤣", rarity: "uncommon"},
    "wink" => %{price: 20, name: "Wink", emoji: "😉", rarity: "common"},
    "angel" => %{price: 45, name: "Angel", emoji: "😇", rarity: "rare"},
    "devil" => %{price: 45, name: "Devil", emoji: "😈", rarity: "rare"},

    # Animals
    "cat" => %{price: 25, name: "Cat", emoji: "🐱", rarity: "common"},
    "dog" => %{price: 25, name: "Dog", emoji: "🐶", rarity: "common"},
    "bear" => %{price: 40, name: "Bear", emoji: "🐻", rarity: "uncommon"},
    "lion" => %{price: 65, name: "Lion", emoji: "🦁", rarity: "rare"},
    "elephant" => %{price: 55, name: "Elephant", emoji: "🐘", rarity: "rare"},
    "eagle" => %{price: 70, name: "Eagle", emoji: "🦅", rarity: "rare"},
    "dragon" => %{price: 180, name: "Dragon", emoji: "🐉", rarity: "epic"},
    "phoenix" => %{price: 350, name: "Phoenix", emoji: "🔥🦅", rarity: "legendary"},

    # Luxury
    "diamond" => %{price: 200, name: "Diamond", emoji: "💎", rarity: "epic"},
    "trophy" => %{price: 100, name: "Trophy", emoji: "🏆", rarity: "rare"},
    "rocket" => %{price: 120, name: "Rocket", emoji: "🚀", rarity: "epic"},
    "money_bag" => %{price: 250, name: "Money Bag", emoji: "💰", rarity: "epic"},
    "unicorn" => %{price: 300, name: "Unicorn", emoji: "🦄", rarity: "legendary"},
    "rainbow" => %{price: 500, name: "Rainbow", emoji: "🌈", rarity: "legendary"},
    "sports_car" => %{price: 800, name: "Sports Car", emoji: "🏎️", rarity: "legendary"},
    "mansion" => %{price: 1200, name: "Mansion", emoji: "🏰", rarity: "legendary"},
    "yacht" => %{price: 2500, name: "Yacht", emoji: "🛥️", rarity: "mythic"},
    "private_jet" => %{price: 5000, name: "Private Jet", emoji: "🛩️", rarity: "mythic"},

    # Food
    "coffee" => %{price: 35, name: "Coffee", emoji: "☕", rarity: "uncommon"},
    "pizza" => %{price: 45, name: "Pizza", emoji: "🍕", rarity: "uncommon"},
    "cake" => %{price: 55, name: "Birthday Cake", emoji: "🎂", rarity: "rare"},
    "champagne" => %{price: 80, name: "Champagne", emoji: "🍾", rarity: "rare"},
    "donut" => %{price: 25, name: "Donut", emoji: "🍩", rarity: "common"},
    "ice_cream" => %{price: 30, name: "Ice Cream", emoji: "🍦", rarity: "uncommon"},
    "burger" => %{price: 40, name: "Burger", emoji: "🍔", rarity: "uncommon"},
    "sushi" => %{price: 60, name: "Sushi", emoji: "🍣", rarity: "rare"},
    "lobster" => %{price: 120, name: "Lobster", emoji: "🦞", rarity: "epic"},
    "caviar" => %{price: 300, name: "Caviar", emoji: "🥄", rarity: "legendary"},

    # Travel
    "beach" => %{price: 400, name: "Beach Vacation", emoji: "🏖️", rarity: "legendary"},
    "mountain" => %{price: 350, name: "Mountain Trip", emoji: "🏔️", rarity: "legendary"},
    "city_break" => %{price: 300, name: "City Break", emoji: "🏙️", rarity: "legendary"},
    "safari" => %{price: 800, name: "Safari Adventure", emoji: "🦓", rarity: "legendary"},
    "cruise" => %{price: 1500, name: "Luxury Cruise", emoji: "🛳️", rarity: "mythic"},
    "space_trip" => %{price: 15000, name: "Space Trip", emoji: "🚀🌌", rarity: "ultimate"},

    # Ultra Premium
    "golden_crown" => %{price: 1000, name: "Golden Crown", emoji: "👑✨", rarity: "mythic"},
    "diamond_ring" => %{price: 2000, name: "Diamond Ring", emoji: "💍", rarity: "mythic"},
    "golden_statue" => %{price: 3500, name: "Golden Statue", emoji: "🗿✨", rarity: "mythic"},
    "treasure_chest" => %{price: 5000, name: "Treasure Chest", emoji: "💰⭐", rarity: "ultimate"},
    "palace" => %{price: 8000, name: "Royal Palace", emoji: "🏰👑", rarity: "ultimate"},
    "island" => %{price: 12000, name: "Private Island", emoji: "🏝️🌴", rarity: "ultimate"},
    "galaxy" => %{price: 25000, name: "Own a Galaxy", emoji: "🌌⭐", rarity: "ultimate"},
    "universe" => %{price: 50000, name: "The Universe", emoji: "🌌✨🪐", rarity: "ultimate"},

    # Nature
    "flower" => %{price: 20, name: "Flower", emoji: "🌸", rarity: "common"},
    "rose" => %{price: 45, name: "Rose", emoji: "🌹", rarity: "uncommon"},
    "bouquet" => %{price: 85, name: "Bouquet", emoji: "💐", rarity: "rare"},
    "tree" => %{price: 60, name: "Tree", emoji: "🌳", rarity: "rare"},
    "forest" => %{price: 200, name: "Forest", emoji: "🌲🌳", rarity: "epic"},
    "garden" => %{price: 400, name: "Garden Paradise", emoji: "🌺🌸🌼", rarity: "legendary"},
    "aurora" => %{price: 800, name: "Aurora Borealis", emoji: "🌌💚", rarity: "legendary"},

    # Sports
    "soccer_ball" => %{price: 30, name: "Soccer Ball", emoji: "⚽", rarity: "uncommon"},
    "basketball" => %{price: 35, name: "Basketball", emoji: "🏀", rarity: "uncommon"},
    "volleyball" => %{price: 25, name: "Volleyball", emoji: "🏐", rarity: "common"},
    "tennis" => %{price: 40, name: "Tennis", emoji: "🎾", rarity: "uncommon"},
    "medal" => %{price: 150, name: "Gold Medal", emoji: "🥇", rarity: "epic"},
    "championship" => %{price: 500, name: "Championship", emoji: "🏆⭐", rarity: "legendary"},
    "olympics" => %{price: 1000, name: "Olympic Victory", emoji: "🥇🌟", rarity: "mythic"},

    # Celestial
    "moon" => %{price: 100, name: "Moon", emoji: "🌙", rarity: "rare"},
    "sun" => %{price: 150, name: "Sun", emoji: "☀️", rarity: "epic"},
    "shooting_star" => %{price: 250, name: "Shooting Star", emoji: "💫", rarity: "epic"},
    "constellation" => %{price: 600, name: "Constellation", emoji: "✨⭐✨", rarity: "legendary"},
    "supernova" => %{price: 1500, name: "Supernova", emoji: "💥⭐", rarity: "mythic"},
    "black_hole" => %{price: 3000, name: "Black Hole", emoji: "🕳️✨", rarity: "mythic"},
    "big_bang" => %{price: 10000, name: "Big Bang", emoji: "💥🌌", rarity: "ultimate"}
  }

  ## CREATE

  @doc """
  Send a gift from one user to another.
  Handles wallet debit/credit and commission calculation.
  """
  def send_gift(attrs) do
    sender_id = attrs["senderId"] || attrs[:sender_id]
    recipient_id = attrs["recipientId"] || attrs[:recipient_id]
    gift_id = attrs["giftId"] || attrs[:gift_id]
    context = attrs["context"] || attrs[:context] || "chat"
    context_id = attrs["contextId"] || attrs[:context_id]
    message = attrs["message"] || attrs[:message]

    # Validate sender and recipient are different
    if sender_id == recipient_id do
      {:error, "Cannot send gift to yourself"}
    else
      # Get gift details from catalog
      case Map.get(@gift_catalog, gift_id) do
        nil ->
          {:error, "Invalid gift ID"}

        gift_info ->
          # Calculate commission
          {recipient_amount, platform_commission} = calculate_commission(gift_info.price)

          # Use transaction to ensure atomicity
          Repo.transaction(fn ->
            # Debit sender's wallet
            case Wallets.debit_wallet(sender_id, gift_info.price, "gift_sent") do
              {:ok, _} ->
                # Credit recipient's wallet
                case Wallets.credit_wallet(recipient_id, recipient_amount, "gift_received") do
                  {:ok, _} ->
                    # Create gift transaction record
                    %GiftTransaction{}
                    |> GiftTransaction.changeset(%{
                      gift_id: gift_id,
                      gift_name: gift_info.name,
                      gift_emoji: gift_info.emoji,
                      gift_rarity: gift_info.rarity,
                      price: gift_info.price,
                      recipient_amount: recipient_amount,
                      platform_commission: platform_commission,
                      context: context,
                      context_id: context_id,
                      message: message,
                      sender_id: sender_id,
                      recipient_id: recipient_id
                    })
                    |> Repo.insert!()

                  {:error, reason} ->
                    Repo.rollback(reason)
                end

              {:error, reason} ->
                Repo.rollback(reason)
            end
          end)
      end
    end
  end

  @doc """
  Calculate platform commission from gift price.
  Returns {recipient_amount, platform_commission}.
  """
  def calculate_commission(price) do
    commission = trunc(price * @default_commission_rate)
    recipient_amount = price - commission
    {recipient_amount, commission}
  end

  ## READ

  @doc """
  Get gift transaction history for a user (sent + received).
  """
  def get_user_gift_history(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    GiftTransaction
    |> where([g], g.sender_id == ^user_id or g.recipient_id == ^user_id)
    |> order_by([g], desc: g.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Get gifts sent by a user.
  """
  def get_sent_gifts(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    GiftTransaction
    |> where([g], g.sender_id == ^user_id)
    |> order_by([g], desc: g.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Get gifts received by a user.
  """
  def get_received_gifts(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    GiftTransaction
    |> where([g], g.recipient_id == ^user_id)
    |> order_by([g], desc: g.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Get gift statistics for a user.
  """
  def get_user_gift_stats(user_id) do
    sent_query = from g in GiftTransaction,
      where: g.sender_id == ^user_id,
      select: %{
        total_sent: count(g.id),
        total_spent: sum(g.price)
      }

    received_query = from g in GiftTransaction,
      where: g.recipient_id == ^user_id,
      select: %{
        total_received: count(g.id),
        total_earned: sum(g.recipient_amount)
      }

    sent_stats = Repo.one(sent_query) || %{total_sent: 0, total_spent: 0}
    received_stats = Repo.one(received_query) || %{total_received: 0, total_earned: 0}

    Map.merge(sent_stats, received_stats)
  end

  @doc """
  Get gift catalog.
  """
  def get_gift_catalog do
    @gift_catalog
    |> Enum.map(fn {id, gift} ->
      {recipient_amount, platform_commission} = calculate_commission(gift.price)

      Map.merge(gift, %{
        id: id,
        recipient_amount: recipient_amount,
        platform_commission: platform_commission
      })
    end)
  end

  @doc """
  Get a specific gift transaction.
  """
  def get_gift_transaction(transaction_id) do
    Repo.get(GiftTransaction, transaction_id)
  end

  ## ADMIN/STATS

  @doc """
  Get platform commission summary (admin only).
  """
  def get_platform_commission_summary do
    query = from g in GiftTransaction,
      select: %{
        total_transactions: count(g.id),
        total_revenue: sum(g.price),
        total_commission: sum(g.platform_commission)
      }

    Repo.one(query) || %{total_transactions: 0, total_revenue: 0, total_commission: 0}
  end

  @doc """
  Get top gift senders (admin only).
  """
  def get_top_gift_senders(limit \\ 10) do
    GiftTransaction
    |> group_by([g], g.sender_id)
    |> select([g], %{
      user_id: g.sender_id,
      total_gifts: count(g.id),
      total_spent: sum(g.price)
    })
    |> order_by([g], desc: sum(g.price))
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Get top gift receivers (admin only).
  """
  def get_top_gift_receivers(limit \\ 10) do
    GiftTransaction
    |> group_by([g], g.recipient_id)
    |> select([g], %{
      user_id: g.recipient_id,
      total_gifts: count(g.id),
      total_earned: sum(g.recipient_amount)
    })
    |> order_by([g], desc: sum(g.recipient_amount))
    |> limit(^limit)
    |> Repo.all()
  end
end
