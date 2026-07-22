export interface ApnsPayload {
  title: string;
  body: string;
  data: Record<string, string | null>;
}

export type SendResult =
  | { ok: true }
  | { ok: false; retryable: boolean; unregistered: boolean; detail: string };

export interface PushTransport {
  readonly name: string;
  send(token: string, payload: ApnsPayload): Promise<SendResult>;
}

/** Today's transport: no Apple Developer .p8 key exists. */
export class NoopTransport implements PushTransport {
  readonly name = "noop";
  send(): Promise<SendResult> {
    return Promise.resolve({
      ok: false,
      retryable: true,
      unregistered: false,
      detail: "no APNs key configured",
    });
  }
}

export class ApnsTransport implements PushTransport {
  readonly name = "apns";
  private jwt: string | null = null;
  private jwtIssuedAt = 0;

  constructor(
    private readonly keyP8: string,
    private readonly keyId: string,
    private readonly teamId: string,
    private readonly topic: string,
    private readonly host = "https://api.push.apple.com",
  ) {}

  /** APNs rejects tokens older than 1h; refresh at 50m. */
  private async authToken(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (this.jwt && now - this.jwtIssuedAt < 3000) return this.jwt;

    const header = { alg: "ES256", kid: this.keyId };
    const claims = { iss: this.teamId, iat: now };
    const b64 = (o: unknown) =>
      btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    const signingInput = `${b64(header)}.${b64(claims)}`;

    const pem = this.keyP8.replace(/-----[A-Z ]+-----/g, "").replace(/\s/g, "");
    const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
    const key = await crypto.subtle.importKey(
      "pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
    );
    const sig = await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput),
    );
    const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

    this.jwt = `${signingInput}.${sigB64}`;
    this.jwtIssuedAt = now;
    return this.jwt;
  }

  async send(token: string, payload: ApnsPayload): Promise<SendResult> {
    const jwt = await this.authToken();
    const res = await fetch(`${this.host}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": this.topic,
        "apns-push-type": "alert",
      },
      body: JSON.stringify({
        aps: { alert: { title: payload.title, body: payload.body }, sound: "default" },
        ...payload.data,
      }),
    });

    if (res.ok) return { ok: true };
    const detail = await res.text();
    // 410 Unregistered / 400 BadDeviceToken: the token is dead, prune it.
    const unregistered = res.status === 410 || detail.includes("BadDeviceToken");
    return {
      ok: false,
      unregistered,
      retryable: res.status === 429 || res.status >= 500,
      detail,
    };
  }
}

/** Picks the transport from the environment. Absent secrets ⇒ no-op. */
export function resolveTransport(): PushTransport {
  const p8 = Deno.env.get("APNS_KEY_P8");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const topic = Deno.env.get("APNS_TOPIC");
  if (p8 && keyId && teamId && topic) {
    return new ApnsTransport(p8, keyId, teamId, topic);
  }
  return new NoopTransport();
}
