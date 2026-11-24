import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import * as SecureStore from 'expo-secure-store';

import { refreshTokens, type TokenSet } from './microsoft';
import { deleteSecret, readSecret, saveSecret } from './storage';

export type Session = TokenSet & {
  displayName: string;
  clientId: string;
};

type AuthContextValue = {
  ready: boolean;
  session: Session | null;
  savedClientId: string;
  tmdbKey: string | null;
  saveSession: (session: Session) => Promise<void>;
  saveClientId: (clientId: string) => Promise<void>;
  setTmdbKey: (value: string) => Promise<void>;
  signOut: () => Promise<void>;
  getToken: () => Promise<string>;
};

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [ready, setReady] = useState(false);
  const [session, setSession] = useState<Session | null>(null);
  const [savedClientId, setSavedClientId] = useState('');
  const [tmdbKey, setTmdbKeyState] = useState<string | null>(null);
  const sessionRef = useRef<Session | null>(null);
  const refreshRef = useRef<Promise<string | null> | null>(null);

  useEffect(() => {
    sessionRef.current = session;
  }, [session]);

  useEffect(() => {
    let cancelled = false;

    const boot = async () => {
      const [savedSession, clientId, savedTmdb] = await Promise.all([
        readSecret('session'),
        SecureStore.getItemAsync('clientId'),
        SecureStore.getItemAsync('tmdbKey'),
      ]);
      if (cancelled) return;
      setSavedClientId(clientId ?? '');
      setTmdbKeyState(savedTmdb);

      if (savedSession) {
        try {
          const parsed = JSON.parse(savedSession) as Session;
          const current =
            parsed.expiresAt - 60_000 > Date.now() ? parsed : await renewedSession(parsed);
          await saveSecret('session', JSON.stringify(current));
          if (!cancelled) {
            sessionRef.current = current;
            setSession(current);
          }
        } catch {
          await deleteSecret('session');
        }
      }
      if (!cancelled) setReady(true);
    };

    void boot();
    return () => {
      cancelled = true;
    };
  }, []);

  const saveSession = useCallback(async (next: Session) => {
    await saveSecret('session', JSON.stringify(next));
    sessionRef.current = next;
    setSession(next);
  }, []);

  const saveClientId = useCallback(async (clientId: string) => {
    await SecureStore.setItemAsync('clientId', clientId);
    setSavedClientId(clientId);
  }, []);

  const setTmdbKey = useCallback(async (value: string) => {
    const trimmed = value.trim();
    if (trimmed) await SecureStore.setItemAsync('tmdbKey', trimmed);
    else await SecureStore.deleteItemAsync('tmdbKey').catch(() => undefined);
    setTmdbKeyState(trimmed || null);
  }, []);

  const signOut = useCallback(async () => {
    await deleteSecret('session');
    sessionRef.current = null;
    setSession(null);
  }, []);

  const getToken = useCallback(async () => {
    const current = sessionRef.current;
    if (!current) throw new Error('เซสชันหมดอายุ เข้าสู่ระบบอีกครั้ง');
    if (current.expiresAt - 60_000 > Date.now()) return current.accessToken;

    if (!refreshRef.current) {
      refreshRef.current = renewedSession(current)
        .then(async (next) => {
          await saveSecret('session', JSON.stringify(next));
          sessionRef.current = next;
          setSession(next);
          return next.accessToken;
        })
        .catch(async () => {
          await deleteSecret('session');
          sessionRef.current = null;
          setSession(null);
          return null;
        })
        .finally(() => {
          refreshRef.current = null;
        });
    }

    const token = await refreshRef.current;
    if (!token) throw new Error('เซสชันหมดอายุ เข้าสู่ระบบอีกครั้ง');
    return token;
  }, []);

  const value = useMemo(
    () => ({ ready, session, savedClientId, tmdbKey, saveSession, saveClientId, setTmdbKey, signOut, getToken }),
    [ready, session, savedClientId, tmdbKey, saveSession, saveClientId, setTmdbKey, signOut, getToken],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

async function renewedSession(session: Session): Promise<Session> {
  const tokens = await refreshTokens(session.clientId, session.refreshToken);
  return { ...session, ...tokens };
}

export function useAuth(): AuthContextValue {
  const value = useContext(AuthContext);
  if (!value) throw new Error('AuthProvider is missing');
  return value;
}
