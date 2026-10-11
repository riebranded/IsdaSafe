// Firebase Cloud Messaging (HTTP v1) for the edge functions that push to
// phones (send-push, send-test-push). Needs the FCM_SERVICE_ACCOUNT secret:
// the whole JSON key file from Firebase console -> Project settings ->
// Service accounts -> Generate new private key.
import { importPKCS8, SignJWT } from "npm:jose@5";

export type ServiceAccount = { project_id: string; client_email: string; private_key: string };

export function serviceAccount(): ServiceAccount | null {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    if (parsed.project_id && parsed.client_email && parsed.private_key) return parsed;
  } catch { /* not JSON */ }
  console.error("fcm: FCM_SERVICE_ACCOUNT isn't a service account key JSON");
  return null;
}

// Google OAuth access token for FCM, cached until shortly before it expires.
let cachedToken: { value: string; expires: number } | null = null;
async function accessToken(account: ServiceAccount): Promise<string> {
  if (cachedToken && cachedToken.expires > Date.now() + 60_000) return cachedToken.value;
  const key = await importPKCS8(account.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const body = await response.json();
  if (!response.ok || typeof body.access_token !== "string") {
    throw new Error(`OAuth token request failed: ${response.status} ${JSON.stringify(body)}`);
  }
  cachedToken = { value: body.access_token, expires: Date.now() + (body.expires_in ?? 3600) * 1000 };
  return cachedToken.value;
}

export type PushMessage = {
  title: string;
  body: string;
  data: Record<string, string>;
  /// Android channel created by the app (system_notification_service.dart).
  channelId: string;
  /// Same tag as the app's own local notification for it, so a phone that
  /// gets both shows it once.
  tag: string;
  urgent: boolean;
};

/// Sends [message] to each token. Returns how many were delivered to FCM,
/// and the tokens FCM says are gone (app uninstalled, data cleared).
export async function sendToTokens(
  account: ServiceAccount,
  tokens: string[],
  message: PushMessage,
): Promise<{ sent: number; gone: string[]; errors: string[] }> {
  const bearer = await accessToken(account);
  let sent = 0;
  const gone: string[] = [];
  const errors: string[] = [];
  await Promise.all(tokens.map(async (token) => {
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${bearer}` },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: message.title, body: message.body },
            data: message.data,
            android: {
              priority: message.urgent ? "HIGH" : "NORMAL",
              notification: { channel_id: message.channelId, tag: message.tag },
            },
          },
        }),
      },
    );
    if (response.ok) {
      sent++;
      return;
    }
    const raw = await response.text();
    if (response.status === 404 || raw.includes("UNREGISTERED")) {
      gone.push(token);
    } else {
      console.error("fcm: FCM rejected a message:", response.status, raw);
      errors.push(`${response.status}`);
    }
  }));
  return { sent, gone, errors };
}
