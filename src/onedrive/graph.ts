export type DriveItem = {
  id: string;
  name: string;
  size?: number;
  folder?: { childCount: number };
  file?: { mimeType?: string };
  video?: { duration?: number };
  thumbnails?: { large?: { url?: string }; medium?: { url?: string } }[];
};

const VIDEO_EXT = /\.(mp4|m4v|mov|mkv|avi|webm|wmv|mpg|mpeg)$/i;

export function isVideoFile(item: DriveItem): boolean {
  if (item.folder) return false;
  if (item.file?.mimeType?.startsWith('video/')) return true;
  return VIDEO_EXT.test(item.name);
}

async function graphError(response: Response): Promise<string> {
  if (response.status === 401) return 'เซสชันหมดอายุ เข้าสู่ระบบอีกครั้ง';
  if (response.status === 403) return 'บัญชีนี้ยังไม่ได้รับสิทธิ์อ่านไฟล์ใน OneDrive';
  return 'โหลดไฟล์จาก OneDrive ไม่สำเร็จ';
}

export async function listChildren(token: string, folderId: string): Promise<DriveItem[]> {
  const items: DriveItem[] = [];
  let url =
    folderId === 'root'
      ? 'https://graph.microsoft.com/v1.0/me/drive/root/children?$top=200&$expand=thumbnails'
      : `https://graph.microsoft.com/v1.0/me/drive/items/${folderId}/children?$top=200&$expand=thumbnails`;

  while (url) {
    const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!response.ok) throw new Error(await graphError(response));
    const body = (await response.json()) as { value?: DriveItem[]; '@odata.nextLink'?: string };
    items.push(...(body.value ?? []));
    url = body['@odata.nextLink'] ?? '';
  }

  return items;
}

export async function getPlaybackUrl(token: string, itemId: string): Promise<string> {
  const response = await fetch(`https://graph.microsoft.com/v1.0/me/drive/items/${itemId}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw new Error(await graphError(response));
  const body = (await response.json()) as { '@microsoft.graph.downloadUrl'?: string };
  if (!body['@microsoft.graph.downloadUrl']) throw new Error('OneDrive ไม่ได้ให้ลิงก์เล่นไฟล์นี้');
  return body['@microsoft.graph.downloadUrl'];
}

export async function fetchProfileName(token: string): Promise<string> {
  const response = await fetch('https://graph.microsoft.com/v1.0/me?$select=displayName,userPrincipalName', {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) return 'OneDrive';
  const body = (await response.json()) as { displayName?: string; userPrincipalName?: string };
  return body.displayName || body.userPrincipalName || 'OneDrive';
}
