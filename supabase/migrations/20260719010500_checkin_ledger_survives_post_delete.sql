-- Plan 5 final-review fix (Important #3): the check-in ledger must survive
-- the post being deleted.
--
-- group_checkins.post_id was `not null references public.posts(id) on delete
-- cascade`, so deleting a check-in post (via PostService's author-delete path)
-- cascaded into deleting the group_checkins row too — erasing the
-- accountability record and re-opening that window as if it were never
-- answered.
--
-- Product decision: PRESERVE THE LEDGER; the delete menu stays as-is (this is
-- a schema-only fix, no client change to the delete flow). The primary key is
-- (group_id, user_id, window_id) — post_id is not part of it, so nulling it
-- out is safe and keeps the row's identity intact.
--
-- The ledger is the accountability record: it exists to say "this member
-- answered this window." Deleting the post removes the content the member
-- shared, not the fact that they showed up for the window.

alter table public.group_checkins
  drop constraint group_checkins_post_id_fkey;

alter table public.group_checkins
  alter column post_id drop not null;

alter table public.group_checkins
  add constraint group_checkins_post_id_fkey
    foreign key (post_id) references public.posts(id) on delete set null;

comment on column public.group_checkins.post_id is
  'The post the member checked in with. Nullable: deleting the post (author delete) sets this to null via ON DELETE SET NULL rather than cascading, so the ledger row -- the record that this window was answered -- survives.';
