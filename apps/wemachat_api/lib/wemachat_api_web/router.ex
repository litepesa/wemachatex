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

    # Health check endpoint for Fly.io (must be public, no auth)
    get "/health", HealthController, :index

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
    get "/videos/for-you", VideoController, :for_you
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
    post "/videos/:id/view", VideoController, :record_view
    post "/videos/:id/comments", VideoController, :create_comment

    # ==========================================
    # MARKETPLACE ROUTES
    # ==========================================
    # Clone of videos feature with pricing (no 72-hour expiry)

    # Marketplace routes (public)
    get "/marketplace", MarketplaceController, :index
    get "/marketplace/:id", MarketplaceController, :show
    get "/marketplace/:id/comments", MarketplaceController, :comments

    # User-specific marketplace items (public)
    get "/users/:user_id/marketplace", MarketplaceController, :user_items
    get "/users/:user_id/liked-marketplace", MarketplaceController, :liked_items

    # Marketplace routes (authenticated)
    post "/marketplace", MarketplaceController, :create
    put "/marketplace/:id", MarketplaceController, :update
    delete "/marketplace/:id", MarketplaceController, :delete
    post "/marketplace/:id/like", MarketplaceController, :like
    delete "/marketplace/:id/like", MarketplaceController, :unlike
    post "/marketplace/:id/views", MarketplaceController, :increment_views
    post "/marketplace/:id/comments", MarketplaceController, :create_comment
    delete "/marketplace/comments/:id", MarketplaceController, :delete_comment
    post "/marketplace/comments/:id/pin", MarketplaceController, :pin_comment
    delete "/marketplace/comments/:id/pin", MarketplaceController, :unpin_comment
    post "/marketplace/:id/boost", MarketplaceController, :boost

    # Chat routes (all authenticated)
    get "/chats", ChatController, :index
    get "/chats/unread_count", ChatController, :unread_count
    post "/chats", ChatController, :create
    get "/chats/:id", ChatController, :show
    get "/chats/:id/messages", ChatController, :messages
    post "/chats/:id/messages", ChatController, :send_message
    post "/chats/:id/mark-read", ChatController, :mark_read

    # Group chat routes (all authenticated)
    get "/groups", GroupController, :index
    get "/groups/search", GroupController, :search
    post "/groups", GroupController, :create
    get "/groups/:id", GroupController, :show
    put "/groups/:id", GroupController, :update
    delete "/groups/:id", GroupController, :delete

    # Group members
    get "/groups/:id/members", GroupController, :list_members
    post "/groups/:id/members", GroupController, :add_members
    delete "/groups/:id/members/:user_id", GroupController, :remove_member
    post "/groups/:id/members/:user_id/promote", GroupController, :promote_member
    post "/groups/:id/members/:user_id/demote", GroupController, :demote_member

    # Group messages
    get "/groups/:id/messages", GroupController, :list_messages
    post "/groups/:id/messages", GroupController, :send_message
    delete "/groups/:group_id/messages/:message_id", GroupController, :delete_message

    # Status routes (all authenticated)
    get "/statuses", StatusController, :index
    get "/statuses/me", StatusController, :my_statuses
    get "/statuses/user/:id", StatusController, :user_statuses
    post "/statuses", StatusController, :create
    delete "/statuses/:id", StatusController, :delete
    post "/statuses/:id/view", StatusController, :view
    post "/statuses/:id/like", StatusController, :like
    delete "/statuses/:id/unlike", StatusController, :unlike

    # Post routes (public - specific paths MUST come before :id patterns)
    get "/posts/discover", PostController, :discover
    get "/posts/search", PostController, :search
    get "/users/:user_id/posts", PostController, :user_posts

    # Post routes (authenticated - specific paths before :id)
    get "/posts/feed", PostController, :feed
    post "/posts", PostController, :create

    # Post routes with :id param (MUST be after specific paths like /feed, /discover)
    get "/posts/:id", PostController, :show
    get "/posts/:id/comments", PostController, :comments
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

    # ==========================================
    # ADMIN/MODERATOR ENDPOINTS
    # ==========================================
    # All admin routes require authentication
    # TODO: Add AdminOnly middleware when role system is implemented

    # Video moderation
    put "/admin/videos/:id/boost", AdminController, :set_video_boost
    put "/admin/videos/:id/pin", AdminController, :pin_video
    delete "/admin/videos/:id/pin", AdminController, :unpin_video
    put "/admin/videos/:id/visibility", AdminController, :set_video_visibility
    put "/admin/videos/:id/geo-target", AdminController, :set_video_geo_targeting

    # Silent push system (no user notifications)
    put "/admin/videos/:id/push-to-all", AdminController, :activate_push_to_all
    delete "/admin/videos/:id/push-to-all", AdminController, :deactivate_push_to_all
    put "/admin/videos/:id/push-targeting", AdminController, :set_push_targeting
    delete "/admin/videos/:id/push", AdminController, :clear_all_push

    # User moderation
    put "/admin/users/:id/mute", AdminController, :mute_user
    delete "/admin/users/:id/mute", AdminController, :unmute_user
    put "/admin/users/:id/shadowban", AdminController, :shadowban_user
    delete "/admin/users/:id/shadowban", AdminController, :unshadowban_user
    put "/admin/users/:id/reach-multiplier", AdminController, :set_reach_multiplier
    put "/admin/users/:id/creator-content-type", AdminController, :set_creator_content_type
    put "/admin/users/:id/interest-type", AdminController, :set_interest_type
  end
end
