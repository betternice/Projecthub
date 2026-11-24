const TENANT = 'common';
const SCOPE = 'offline_access User.Read Files.Read';
const DEVICE_URL = `https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/devicecode`;
const TOKEN_URL = `https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/token`;

export type TokenSet = {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
};

export type DeviceLogin = {
  userCode: string;
  deviceCode: string;
  verificationUri: string;
  interval: number;
};

type TokenResponse = {
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
  error?: string;
  error_description?: string;
};

function toTokenSet(body: TokenResponse, previousRefreshToken = ''): TokenSet {
  if (!body.access_token) throw new Error(friendlyAuthError(body));
  return {
    accessToken: body.access_token,
    refreshToken: body.refresh_token || previousRefreshToken,
    expiresAt: Date.now() + (body.expires_in ?? 3600) * 1000,
  };
}

export function friendlyAuthError(body: TokenResponse): string {
  const description = body.error_description ?? '';
  const code = description.match(/AADSTS\d+/)?.[0];
  if (description.includes('7000218')) return 'ใน Azure ยังไม่ได้เปิด Allow public client flows';
  if (description.includes('700016')) return 'ไม่พบแอปนี้ ตรวจ Application (client) ID';
  if (description.includes('65001')) return 'บัญชียังไม่ได้อนุญาตให้แอปอ่านไฟล์';
  if (body.error === 'invalid_client') return 'Client ID ไม่ถูกต้อง หรือยังไม่ได้เปิด public client flows';
  return code ? `เข้าสู่ระบบไม่สำเร็จ (${code})` : 'เข้าสู่ระบบไม่สำเร็จ ตรวจการตั้งค่าแอปใน Azure';
}

export async function requestDeviceCode(clientId: string): Promise<DeviceLogin> {
  const response = await fetch(DEVICE_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: clientId, scope: SCOPE }).toString(),
  });
  const body = (await response.json()) as TokenResponse & {
    user_code?: string;
    device_code?: string;
    verification_uri?: string;
    interval?: number;
  };
  if (!response.ok || !body.user_code || !body.device_code || !body.verification_uri) {
    throw new Error(friendlyAuthError(body));
  }
  return {
    userCode: body.user_code,
    deviceCode: body.device_code,
    verificationUri: body.verification_uri,
    interval: body.interval ?? 5,
  };
}

export async function pollDeviceToken(
  clientId: string,
  deviceCode: string,
): Promise<{ status: 'pending' | 'slow_down' | 'expired' | 'denied' } | { status: 'success'; tokens: TokenSet }> {
  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
      client_id: clientId,
      device_code: deviceCode,
    }).toString(),
  });
  const body = (await response.json()) as TokenResponse;
  if (response.ok && body.access_token) return { status: 'success', tokens: toTokenSet(body) };
  if (body.error === 'authorization_pending') return { status: 'pending' };
  if (body.error === 'slow_down') return { status: 'slow_down' };
  if (body.error === 'expired_token') return { status: 'expired' };
  if (body.error === 'authorization_declined' || body.error === 'access_denied') return { status: 'denied' };
  throw new Error(friendlyAuthError(body));
}

export async function refreshTokens(clientId: string, refreshToken: string): Promise<TokenSet> {
  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: clientId,
      grant_type: 'refresh_token',
      refresh_token: refreshToken,
      scope: SCOPE,
    }).toString(),
  });
  const body = (await response.json()) as TokenResponse;
  if (!response.ok) throw new Error(friendlyAuthError(body));
  return toTokenSet(body, refreshToken);
}
