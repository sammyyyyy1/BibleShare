-- At most one friendship row per pair of users, regardless of direction.
-- friendships is empty in prod, so this builds without violations.
create unique index if not exists friendships_unordered_uniq on public.friendships
  (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
