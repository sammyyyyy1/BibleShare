import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { type ApnsPayload, resolveTransport } from "./transport.ts";

const COPY: Record<string, (actor: string, group: string | null) => [string, string]> = {
  post_like: (a) => ["New like", `${a} liked your post`],
  post_comment: (a) => ["New comment", `${a} commented on your post`],
  post_tag: (a) => ["You were tagged", `${a} tagged you in a post`],
  member_checked_in: (a, g) => ["Check-in", `${a} checked in${g ? ` in ${g}` : ""}`],
  checkin_reminder: (_a, g) => ["Time to check in", g ? `${g} is waiting on you` : "Your group is waiting on you"],
  group_invite: (a, g) => ["Group invite", `${a} invited you to ${g ?? "a group"}`],
  friend_request: (a) => ["Friend request", `${a} sent you a friend request`],
  friend_accepted: (a) => ["Friend request accepted", `${a} accepted your friend request`],
};

// MODULE SCOPE, deliberately. ApnsTransport caches its ES256 provider JWT for
// ~50 minutes, but that cache only means anything if the instance outlives a
// single request. Constructing the transport inside the handler would mint a
// brand-new provider JWT on every invocation -- and with the drain cron firing
// once a minute Apple would answer TooManyProviderTokenUpdates, so push would
// fail systemically the day it goes live. An Edge Function isolate is reused
// across invocations while warm, so hoisting this is what makes the cache real.
const transport = resolveTransport();

Deno.serve(async () => {
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // The 1-day window is what keeps the backlog bounded while NoopTransport
  // leaves rows unpushed. Served by notifications_unpushed_idx.
  const since = new Date(Date.now() - 86_400_000).toISOString();
  const { data: pending, error } = await db
    .from("notifications")
    .select("id,recipient_id,type,post_id,group_id,actor:profiles(username),group:groups(name)")
    .is("pushed_at", null)
    .gt("created_at", since)
    .order("created_at", { ascending: true })
    .limit(500);

  if (error) return Response.json({ error: error.message }, { status: 500 });

  // CRITICAL: the no-op transport must NOT stamp pushed_at. If it did, then on
  // the day an APNs key arrives every accumulated notification would already be
  // marked delivered and the first real push would be for whatever happened
  // next, with no way to tell what was silently dropped. Leaving them unpushed
  // makes enabling APNs one secret plus one deploy.
  if (transport.name === "noop") {
    return Response.json({ transport: "noop", pending: pending?.length ?? 0, sent: 0, failed: 0, pruned: 0 });
  }

  // NOT SINGLE-FLIGHT. Rows are selected before pushed_at is stamped, so two
  // overlapping drains would select and send the same rows twice. Unreachable
  // today (nothing schedules this; the only caller is manual invocation), but
  // it becomes reachable the moment the per-minute cron in
  // 20260720010400_push_cron.sql is enabled -- which is why that migration
  // names single-flight as a precondition of switching it on. A session
  // advisory lock is NOT a fix here: the pooler hands out a different
  // connection per request, so the lock would not span these statements.
  let sent = 0, failed = 0, pruned = 0, noTokens = 0;
  for (const n of pending ?? []) {
    const { data: tokens } = await db
      .from("device_tokens").select("token").eq("user_id", n.recipient_id);
    // Counted rather than silently skipped, so "nobody registered a device" is
    // distinguishable from "delivery failed" in the response metrics.
    if (!tokens?.length) { noTokens++; continue; }

    const build = COPY[n.type];
    if (!build) { failed++; continue; }
    // deno-lint-ignore no-explicit-any
    const actorName = (n as any).actor?.username ?? "Someone";
    // deno-lint-ignore no-explicit-any
    const groupName = (n as any).group?.name ?? null;
    const [title, body] = build(actorName, groupName);
    const payload: ApnsPayload = {
      title, body,
      data: { type: n.type, notification_id: n.id, post_id: n.post_id, group_id: n.group_id },
    };

    // One bad row must not strand every remaining row in this tick. A throw
    // here (malformed PEM, DNS failure, socket reset) is treated exactly like a
    // retryable send failure: pushed_at stays null and the next run retries.
    let delivered = false;
    try {
      for (const { token } of tokens) {
        const r = await transport.send(token, payload);
        if (r.ok) { delivered = true; continue; }
        if (r.unregistered) {
          await db.from("device_tokens").delete().eq("token", token);
          pruned++;
        }
      }
    } catch (e) {
      console.error(`[push] send failed for notification ${n.id}:`, e);
    }

    if (delivered) {
      // Guarded on pushed_at still being null so a concurrent drain cannot
      // move an already-stamped timestamp. This bounds the damage of an
      // overlap; it does not prevent the duplicate send itself.
      await db.from("notifications")
        .update({ pushed_at: new Date().toISOString() })
        .eq("id", n.id).is("pushed_at", null);
      sent++;
    } else {
      failed++;  // retryable: pushed_at stays null, next run picks it up
    }
  }

  return Response.json({
    transport: transport.name, pending: pending?.length ?? 0, sent, failed, pruned, noTokens,
  });
});
