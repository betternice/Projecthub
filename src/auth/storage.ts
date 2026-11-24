import * as SecureStore from 'expo-secure-store';

const CHUNK = 1800;

export async function saveSecret(key: string, value: string): Promise<void> {
  const count = Math.max(1, Math.ceil(value.length / CHUNK));
  await SecureStore.setItemAsync(`${key}.count`, String(count));
  for (let index = 0; index < count; index += 1) {
    await SecureStore.setItemAsync(`${key}.${index}`, value.slice(index * CHUNK, (index + 1) * CHUNK));
  }
}

export async function readSecret(key: string): Promise<string | null> {
  const countRaw = await SecureStore.getItemAsync(`${key}.count`);
  if (!countRaw) return null;
  const count = Number(countRaw);
  let value = '';
  for (let index = 0; index < count; index += 1) {
    const part = await SecureStore.getItemAsync(`${key}.${index}`);
    if (part == null) return null;
    value += part;
  }
  return value;
}

export async function deleteSecret(key: string): Promise<void> {
  const countRaw = await SecureStore.getItemAsync(`${key}.count`);
  const count = Number(countRaw ?? 0);
  await SecureStore.deleteItemAsync(`${key}.count`).catch(() => undefined);
  for (let index = 0; index < count; index += 1) {
    await SecureStore.deleteItemAsync(`${key}.${index}`).catch(() => undefined);
  }
}
