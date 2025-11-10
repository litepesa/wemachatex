defmodule WemachatApiWeb.Router do
  use WemachatApiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug :accepts, ["json"]
    plug WemachatApiWeb.Plugs.FirebaseAuth
  end

  scope "/api/v1", WemachatApiWeb do
    pipe_through :api

    # Auth routes (authenticated) - Alias for user sync
    post "/auth/sync", UserController, :sync

    # User routes (public)
    get "/users", UserController, :index
    get "/users/verified", UserController, :verified
    get "/users/featured", UserController, :featured
    get "/users/live", UserController, :live
    get "/users/search", UserController, :search
    get "/users/:id", UserController, :show

    # User routes (authenticated)
    post "/users/sync", UserController, :sync
    put "/users/:id", UserController, :update
    post "/users/:id/follow", UserController, :follow
    delete "/users/:id/follow", UserController, :unfollow
    put "/users/:id/live", UserController, :update_live_status

    # Video routes (public)
    get "/videos/feed", VideoController, :feed
    get "/videos/discover", VideoController, :discover
    get "/videos/search", VideoController, :search
    get "/videos/:id", VideoController, :show
    get "/videos/:id/comments", VideoController, :comments
    get "/users/:user_id/videos", VideoController, :user_videos
    # Legacy support - some clients may call /videos without /feed
    get "/videos", VideoController, :feed

    # Video routes (authenticated)
    post "/videos", VideoController, :create
    put "/videos/:id", VideoController, :update
    delete "/videos/:id", VideoController, :delete
    post "/videos/:id/like", VideoController, :like
    delete "/videos/:id/like", VideoController, :unlike
    post "/videos/:id/share", VideoController, :share
    post "/videos/:id/comments", VideoController, :create_comment

    # Chat routes (all authenticated)
    get "/chats", ChatController, :index
    get "/chats/unread_count", ChatController, :unread_count
    post "/chats", ChatController, :create
    get "/chats/:id", ChatController, :show
    get "/chats/:id/messages", ChatController, :messages

    # Post routes (public)
    get "/posts/discover", PostController, :discover
    get "/posts/search", PostController, :search
    get "/posts/:id", PostController, :show
    get "/posts/:id/comments", PostController, :comments
    get "/users/:user_id/posts", PostController, :user_posts

    # Post routes (authenticated)
    get "/posts/feed", PostController, :feed
    post "/posts", PostController, :create
    put "/posts/:id", PostController, :update
    delete "/posts/:id", PostController, :delete
    post "/posts/:id/like", PostController, :like
    delete "/posts/:id/like", PostController, :unlike
    post "/posts/:id/comments", PostController, :create_comment

    # Wallet routes (all authenticated)
    get "/wallet", WalletController, :show
    get "/wallet/transactions", WalletController, :transactions
    post "/wallet/transfer", WalletController, :transfer
    post "/wallet/earn", WalletController, :earn
    post "/wallet/spend", WalletController, :spend

    # Payment routes (M-Pesa STK Push)
    # Authenticated routes
    post "/payment/initiate", PaymentController, :initiate
    get "/payment/status/:checkout_request_id", PaymentController, :status
    get "/payment/user-info", PaymentController, :user_info
    get "/payment/transactions", PaymentController, :transactions
    # Public route (M-Pesa callback webhook)
    post "/payment/callback", PaymentController, :callback

    # Call routes (all authenticated)
    get "/calls", CallController, :index
    get "/calls/active", CallController, :active
    get "/calls/missed", CallController, :missed
    get "/calls/stats", CallController, :stats
    get "/calls/:id", CallController, :show
    delete "/calls/:id", CallController, :delete

    # Upload routes (all authenticated)
    post "/upload", UploadController, :create
    post "/upload/multiple", UploadController, :create_multiple
    delete "/upload", UploadController, :delete

    # Contact routes (all authenticated)
    get "/contacts", ContactController, :index
    get "/contacts/favorites", ContactController, :favorites
    get "/contacts/search", ContactController, :search
    get "/contacts/blocked", ContactController, :blocked
    post "/contacts", ContactController, :create
    put "/contacts/:contact_user_id", ContactController, :update
    delete "/contacts/:contact_user_id", ContactController, :delete
    post "/contacts/block", ContactController, :block
    delete "/contacts/block/:blocked_id", ContactController, :unblock
    put "/contacts/privacy", ContactController, :update_privacy
    post "/contacts/can-message", ContactController, :can_message
    post "/contacts/can-call", ContactController, :can_call
    post "/contacts/sync", ContactController, :sync

    # Gift routes
    get "/gifts/catalog", GiftController, :get_catalog
    post "/gifts/send", GiftController, :send_gift
    get "/gifts/history/:user_id", GiftController, :get_history
    get "/gifts/stats/:user_id", GiftController, :get_stats

    # ==========================================
    # BROADCAST CHANNELS SYSTEM
    # ==========================================

    # Channel routes (mixed public/authenticated)
    # Public - discovery
    get "/channels", ChannelController, :index
    get "/channels/trending", ChannelController, :trending
    get "/channels/:id", ChannelController, :show

    # Authenticated - management
    get "/channels/subscribed", ChannelController, :subscribed
    post "/channels", ChannelController, :create
    put "/channels/:id", ChannelController, :update
    delete "/channels/:id", ChannelController, :delete

    # Subscription management (authenticated)
    post "/channels/:id/subscribe", ChannelController, :subscribe
    delete "/channels/:id/subscribe", ChannelController, :unsubscribe
    post "/channels/:id/mark-read", ChannelController, :mark_read
    post "/channels/:id/notifications", ChannelController, :toggle_notifications

    # Channel members management (authenticated)
    get "/channels/:id/members", ChannelController, :list_members
    post "/channels/:id/members", ChannelController, :add_member
    delete "/channels/:id/members/:user_id", ChannelController, :remove_member

    # Channel posts routes
    # Public - viewing
    get "/channels/:channel_id/posts", ChannelPostController, :index
    get "/posts/:id", ChannelPostController, :show

    # Authenticated - management
    post "/posts", ChannelPostController, :create
    put "/posts/:id", ChannelPostController, :update
    delete "/posts/:id", ChannelPostController, :delete

    # Post interactions (authenticated)
    post "/posts/:id/like", ChannelPostController, :like
    delete "/posts/:id/like", ChannelPostController, :unlike
    post "/posts/:id/unlock", ChannelPostController, :unlock

    # Comment routes
    # Public - viewing
    get "/posts/:post_id/comments", ChannelCommentController, :index
    get "/comments/:comment_id/replies", ChannelCommentController, :list_replies
    get "/comments/:id", ChannelCommentController, :show

    # Authenticated - management
    post "/comments", ChannelCommentController, :create
    put "/comments/:id", ChannelCommentController, :update
    delete "/comments/:id", ChannelCommentController, :delete

    # Comment interactions (authenticated)
    post "/comments/:id/like", ChannelCommentController, :like
    delete "/comments/:id/like", ChannelCommentController, :unlike
    post "/comments/:id/pin", ChannelCommentController, :pin
    delete "/comments/:id/pin", ChannelCommentController, :unpin
  end
end
