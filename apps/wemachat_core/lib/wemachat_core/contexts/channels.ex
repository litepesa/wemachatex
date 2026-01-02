defmodule WemachatCore.Contexts.Channels do
  @moduledoc """
  The Channels context.
  Handles all business logic for broadcast channels (WhatsApp/Telegram Channels equivalent).

  Includes:
  - Channel CRUD (create, read, update, delete)
  - Post management (text, image, video, audio, document)
  - Multi-threaded comments with unlimited nesting
  - Channel members (up to 8 admins/moderators)
  - Subscriptions with unread tracking
  - Premium content unlocking (80/20 revenue split)
  """

  import Ecto.Query, warn: false
  alias WemachatDatabase.Repo

  alias WemachatDatabase.Schemas.{
    Channel,
    ChannelPost,
    ChannelComment,
    ChannelMember,
    ChannelSubscription,
    PostUnlock
  }

  alias WemachatCore.Contexts.Wallets

  ## CHANNELS - CRUD

  @doc """
  List all channels with optional filtering and pagination.
  """
  def list_channels(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    type = Keyword.get(opts, :type)
    search = Keyword.get(opts, :search)

    query =
      Channel
      |> apply_channel_filters(type, search)
      |> order_by([c], desc: c.subscriber_count, desc: c.inserted_at)
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))

    Repo.all(query)
  end

  @doc """
  List trending channels (sorted by subscriber_count).
  """
  def list_trending_channels(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    Channel
    |> where([c], c.type == :public)
    |> order_by([c], desc: c.subscriber_count)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  List channels a user has subscribed to.
  """
  def list_subscribed_channels(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    offset_value = (page - 1) * per_page

    query =
      from c in Channel,
        join: s in ChannelSubscription,
        on: s.channel_id == c.id and s.user_id == ^user_id,
        order_by: [desc: s.updated_at],
        limit: ^per_page,
        offset: ^offset_value,
        select: c

    Repo.all(query)
  end

  @doc """
  Get a channel by ID.
  """
  def get_channel(id), do: Repo.get(Channel, id)

  @doc """
  Get a channel by name.
  """
  def get_channel_by_name(name), do: Repo.get_by(Channel, name: name)

  @doc """
  Check if a channel name is available.
  Returns true if available, false if taken.
  """
  def is_channel_name_available?(name) do
    name
    |> String.trim()
    |> then(fn trimmed_name ->
      case Repo.get_by(Channel, name: trimmed_name) do
        nil -> true
        _ -> false
      end
    end)
  end

  @doc """
  Create a new channel.
  """
  def create_channel(attrs) do
    %Channel{}
    |> Channel.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update channel information.
  """
  def update_channel(%Channel{} = channel, attrs) do
    channel
    |> Channel.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a channel (only owner can delete).
  """
  def delete_channel(%Channel{} = channel) do
    Repo.delete(channel)
  end

  @doc """
  Check if a user is the owner of a channel.
  """
  def is_channel_owner?(channel_id, user_id) do
    case get_channel(channel_id) do
      nil -> false
      channel -> channel.owner_id == user_id
    end
  end

  @doc """
  Check if a user is an admin or moderator of a channel.
  """
  def is_channel_member?(channel_id, user_id) do
    query =
      from m in ChannelMember,
        where: m.channel_id == ^channel_id and m.user_id == ^user_id

    Repo.exists?(query)
  end

  @doc """
  Check if a user can post in a channel (owner, admin, or moderator).
  """
  def can_post_in_channel?(channel_id, user_id) do
    is_channel_owner?(channel_id, user_id) or is_channel_member?(channel_id, user_id)
  end

  ## CHANNEL POSTS

  @doc """
  List posts in a channel.
  """
  def list_channel_posts(channel_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    ChannelPost
    |> where([p], p.channel_id == ^channel_id)
    |> order_by([p], desc: p.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Get a single post by ID.
  """
  def get_post(id), do: Repo.get(ChannelPost, id)

  @doc """
  Create a new post in a channel.
  """
  def create_post(attrs) do
    %ChannelPost{}
    |> ChannelPost.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a post (text only).
  """
  def update_post(%ChannelPost{} = post, attrs) do
    post
    |> ChannelPost.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a post.
  """
  def delete_post(%ChannelPost{} = post) do
    Repo.delete(post)
  end

  @doc """
  Increment post views count.
  """
  def increment_post_views(post_id) do
    post = Repo.get!(ChannelPost, post_id)

    post
    |> ChannelPost.stats_changeset(%{views: post.views + 1})
    |> Repo.update()
  end

  @doc """
  Like a post.
  """
  def like_post(post_id) do
    post = Repo.get!(ChannelPost, post_id)

    post
    |> ChannelPost.stats_changeset(%{likes: post.likes + 1})
    |> Repo.update()
  end

  @doc """
  Unlike a post.
  """
  def unlike_post(post_id) do
    post = Repo.get!(ChannelPost, post_id)

    post
    |> ChannelPost.stats_changeset(%{likes: max(0, post.likes - 1)})
    |> Repo.update()
  end

  ## PREMIUM POST UNLOCKING

  @doc """
  Check if a user has unlocked a premium post.
  """
  def has_unlocked_post?(post_id, user_id) do
    query =
      from u in PostUnlock,
        where: u.post_id == ^post_id and u.user_id == ^user_id

    Repo.exists?(query)
  end

  @doc """
  Unlock a premium post with coins (80/20 revenue split).
  Returns {:ok, unlock} or {:error, reason}.
  """
  def unlock_premium_post(post_id, user_id) do
    post = Repo.get(ChannelPost, post_id)

    cond do
      is_nil(post) ->
        {:error, :post_not_found}

      not post.is_premium ->
        {:error, :not_premium_post}

      has_unlocked_post?(post_id, user_id) ->
        {:error, :already_unlocked}

      true ->
        # Get the channel to find the creator
        channel = Repo.get!(Channel, post.channel_id)
        creator_id = channel.owner_id
        price = post.price_coins

        Repo.transaction(fn ->
          # Deduct coins from user
          case Wallets.debit_wallet(user_id, price, "spend", %{
                 "description" => "Unlocked premium post",
                 "post_id" => post_id
               }) do
            {:ok, {_wallet, _transaction}} ->
              # Create unlock record
              unlock_attrs = %{
                "post_id" => post_id,
                "user_id" => user_id,
                "coins_paid" => price
              }

              unlock =
                %PostUnlock{}
                |> PostUnlock.create_changeset(unlock_attrs)
                |> Repo.insert!()

              # Credit 80% to creator
              creator_revenue = unlock.creator_revenue

              Wallets.credit_wallet(creator_id, creator_revenue, "earn", %{
                "description" => "Premium post unlocked",
                "post_id" => post_id
              })

              unlock

            {:error, reason} ->
              Repo.rollback(reason)
          end
        end)
        |> case do
          {:ok, unlock} -> {:ok, unlock}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  ## COMMENTS

  @doc """
  List comments for a post (top-level comments only).
  """
  def list_post_comments(post_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    ChannelComment
    |> where([c], c.post_id == ^post_id and is_nil(c.parent_id))
    |> order_by([c], desc: c.is_pinned, desc: c.likes, desc: c.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  List replies to a comment.
  """
  def list_comment_replies(parent_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    ChannelComment
    |> where([c], c.parent_id == ^parent_id)
    |> order_by([c], asc: c.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Get a comment by ID.
  """
  def get_comment(id), do: Repo.get(ChannelComment, id)

  @doc """
  Create a new comment.
  If parent_id is provided, updates the path after insertion.
  """
  def create_comment(attrs) do
    Repo.transaction(fn ->
      comment =
        %ChannelComment{}
        |> ChannelComment.create_changeset(attrs)
        |> Repo.insert!()

      # If this is a reply, update the path
      if comment.parent_id do
        parent = Repo.get!(ChannelComment, comment.parent_id)

        comment
        |> ChannelComment.update_path_changeset(parent.path, parent.id)
        |> Repo.update!()
      else
        comment
      end
    end)
    |> case do
      {:ok, comment} -> {:ok, comment}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Update a comment (text only).
  """
  def update_comment(%ChannelComment{} = comment, attrs) do
    comment
    |> ChannelComment.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a comment.
  """
  def delete_comment(%ChannelComment{} = comment) do
    Repo.delete(comment)
  end

  @doc """
  Like a comment.
  """
  def like_comment(comment_id) do
    comment = Repo.get!(ChannelComment, comment_id)

    comment
    |> ChannelComment.stats_changeset(%{likes: comment.likes + 1})
    |> Repo.update()
  end

  @doc """
  Unlike a comment.
  """
  def unlike_comment(comment_id) do
    comment = Repo.get!(ChannelComment, comment_id)

    comment
    |> ChannelComment.stats_changeset(%{likes: max(0, comment.likes - 1)})
    |> Repo.update()
  end

  @doc """
  Pin a comment (only one comment can be pinned per post).
  """
  def pin_comment(comment_id) do
    comment = Repo.get!(ChannelComment, comment_id)

    Repo.transaction(fn ->
      # Unpin all other comments on this post
      from(c in ChannelComment,
        where: c.post_id == ^comment.post_id and c.id != ^comment_id and c.is_pinned == true
      )
      |> Repo.update_all(set: [is_pinned: false])

      # Pin this comment
      comment
      |> ChannelComment.pin_changeset(true)
      |> Repo.update!()
    end)
    |> case do
      {:ok, comment} -> {:ok, comment}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Unpin a comment.
  """
  def unpin_comment(comment_id) do
    comment = Repo.get!(ChannelComment, comment_id)

    comment
    |> ChannelComment.pin_changeset(false)
    |> Repo.update()
  end

  ## CHANNEL MEMBERS (ADMINS/MODERATORS)

  @doc """
  List members of a channel.
  """
  def list_channel_members(channel_id) do
    ChannelMember
    |> where([m], m.channel_id == ^channel_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Get a channel member by channel and user.
  """
  def get_channel_member(channel_id, user_id) do
    Repo.get_by(ChannelMember, channel_id: channel_id, user_id: user_id)
  end

  @doc """
  Count channel members.
  """
  def count_channel_members(channel_id) do
    ChannelMember
    |> where([m], m.channel_id == ^channel_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Add a member to a channel (admin or moderator).
  Enforces max 8 members per channel.
  """
  def add_channel_member(attrs) do
    channel_id = attrs["channel_id"] || attrs[:channel_id]
    current_count = count_channel_members(channel_id)

    if current_count >= ChannelMember.max_members_per_channel() do
      {:error, :max_members_reached}
    else
      %ChannelMember{}
      |> ChannelMember.create_changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Remove a member from a channel.
  """
  def remove_channel_member(%ChannelMember{} = member) do
    Repo.delete(member)
  end

  @doc """
  Update a member's role.
  """
  def update_member_role(%ChannelMember{} = member, new_role) do
    member
    |> ChannelMember.role_changeset(new_role)
    |> Repo.update()
  end

  ## SUBSCRIPTIONS

  @doc """
  Subscribe to a channel.
  """
  def subscribe_to_channel(channel_id, user_id) do
    attrs = %{
      "channel_id" => channel_id,
      "user_id" => user_id
    }

    %ChannelSubscription{}
    |> ChannelSubscription.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Unsubscribe from a channel.
  """
  def unsubscribe_from_channel(channel_id, user_id) do
    case Repo.get_by(ChannelSubscription, channel_id: channel_id, user_id: user_id) do
      nil -> {:error, :not_subscribed}
      subscription -> Repo.delete(subscription)
    end
  end

  @doc """
  Check if a user is subscribed to a channel.
  """
  def is_subscribed?(channel_id, user_id) do
    query =
      from s in ChannelSubscription,
        where: s.channel_id == ^channel_id and s.user_id == ^user_id

    Repo.exists?(query)
  end

  @doc """
  Get a user's subscription to a channel.
  """
  def get_subscription(channel_id, user_id) do
    Repo.get_by(ChannelSubscription, channel_id: channel_id, user_id: user_id)
  end

  @doc """
  Mark all posts in a channel as read for a user.
  """
  def mark_channel_as_read(channel_id, user_id) do
    case get_subscription(channel_id, user_id) do
      nil -> {:error, :not_subscribed}
      subscription ->
        subscription
        |> ChannelSubscription.mark_read_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Toggle notification preferences for a subscription.
  """
  def toggle_notifications(channel_id, user_id, enabled) do
    case get_subscription(channel_id, user_id) do
      nil -> {:error, :not_subscribed}
      subscription ->
        subscription
        |> ChannelSubscription.notification_changeset(enabled)
        |> Repo.update()
    end
  end

  ## STATISTICS

  @doc """
  Get channel statistics.
  """
  def get_channel_stats(channel_id) do
    channel = Repo.get(Channel, channel_id)

    if is_nil(channel) do
      nil
    else
      %{
        subscriber_count: channel.subscriber_count,
        post_count: channel.post_count,
        type: channel.type,
        is_verified: channel.is_verified
      }
    end
  end

  ## PRIVATE HELPERS

  defp apply_channel_filters(query, type, search) do
    query
    |> filter_by_type(type)
    |> filter_by_search(search)
  end

  defp filter_by_type(query, nil), do: query

  defp filter_by_type(query, type) do
    where(query, [c], c.type == ^type)
  end

  defp filter_by_search(query, nil), do: query
  defp filter_by_search(query, ""), do: query

  defp filter_by_search(query, search) do
    search_pattern = "%#{search}%"

    where(
      query,
      [c],
      ilike(c.name, ^search_pattern) or ilike(c.description, ^search_pattern)
    )
  end
end
