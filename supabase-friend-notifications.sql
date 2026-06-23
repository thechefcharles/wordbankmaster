-- Friend request bell notifications  (migration: friend_request_notifications)
-- add_friend now _notify()s the addressee ("👋 New friend request") on a NEW
-- request (idempotent re-sends don't re-notify). Accepting (respond_friend_request
-- or auto-accept in add_friend) _notify()s the requester ("🤝 accepted").
-- All carry data.route='friends' so tapping the bell notification opens the
-- Friends page (Requests inbox, where Accept/Decline live).

-- Update (migration: friend_request_notif_username): the friend_request
-- notification now carries data.from_username so the bell panel can Accept/Decline
-- inline (respond_friend_request(from_username, accept)).
