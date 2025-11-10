defmodule WemachatDatabase.Schemas.PostUnlock do
  @moduledoc """
  Schema for tracking premium post unlocks.
  Records when a user pays coins to unlock a premium post.
  Revenue split: 80% to creator, 20% to platform.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WemachatDatabase.Schemas.ChannelPost

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, except: [:__meta__, :post]}

  schema "post_unlocks" do
    field :user_id, :string
    field :coins_paid, :integer
    field :creator_revenue, :integer
    field :platform_revenue, :integer

    belongs_to :post, ChannelPost, foreign_key: :post_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new post unlock.
  Automatically calculates revenue split (80/20).
  """
  def create_changeset(unlock, attrs) do
    unlock
    |> cast(attrs, [:post_id, :user_id, :coins_paid])
    |> validate_required([:post_id, :user_id, :coins_paid])
    |> validate_number(:coins_paid, greater_than: 0)
    |> calculate_revenue_split()
    |> unique_constraint([:post_id, :user_id],
      name: :post_unlocks_post_id_user_id_index,
      message: "user has already unlocked this post"
    )
    |> foreign_key_constraint(:post_id)
  end

  # Private functions

  defp calculate_revenue_split(changeset) do
    coins_paid = get_field(changeset, :coins_paid)

    if coins_paid do
      # 80% to creator, 20% to platform
      creator_revenue = floor(coins_paid * 0.8)
      platform_revenue = coins_paid - creator_revenue

      changeset
      |> put_change(:creator_revenue, creator_revenue)
      |> put_change(:platform_revenue, platform_revenue)
    else
      changeset
    end
  end
end
