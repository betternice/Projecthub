import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Linking,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import * as Clipboard from 'expo-clipboard';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useAuth } from '../auth/AuthContext';
import { pollDeviceToken, requestDeviceCode, type DeviceLogin } from '../auth/microsoft';
import { fetchProfileName } from '../onedrive/graph';
import { font, theme } from '../theme';

const GUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type PendingLogin = DeviceLogin & { clientId: string };

type ConnectSheetProps = {
  onClose: () => void;
};

export function ConnectSheet({ onClose }: ConnectSheetProps) {
  const insets = useSafeAreaInsets();
  const { session, savedClientId, saveClientId, saveSession, signOut } = useAuth();
  const [clientId, setClientId] = useState(savedClientId);
  const [pending, setPending] = useState<PendingLogin | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const clientReady = GUID.test(clientId.trim());

  useEffect(() => {
    setClientId(savedClientId);
  }, [savedClientId]);

  useEffect(() => {
    if (!pending) return undefined;
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout>;
    let wait = pending.interval;

    const tick = async () => {
      try {
        const result = await pollDeviceToken(pending.clientId, pending.deviceCode);
        if (cancelled) return;
        if (result.status === 'pending' || result.status === 'slow_down') {
          if (result.status === 'slow_down') wait += 5;
          timer = setTimeout(tick, wait * 1000);
          return;
        }
        if (result.status === 'success') {
          const displayName = await fetchProfileName(result.tokens.accessToken);
          await saveSession({ ...result.tokens, displayName, clientId: pending.clientId });
          onClose();
          return;
        }
        setPending(null);
        setError(result.status === 'expired' ? 'รหัสหมดอายุแล้ว ลองเชื่อมใหม่' : 'ยกเลิกการเชื่อม OneDrive');
      } catch (cause) {
        if (!cancelled) {
          setPending(null);
          setError(cause instanceof Error ? cause.message : 'เชื่อม OneDrive ไม่สำเร็จ');
        }
      }
    };

    timer = setTimeout(tick, wait * 1000);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [onClose, pending, saveSession]);

  const start = async () => {
    const id = clientId.trim();
    setError(null);
    setBusy(true);
    try {
      await saveClientId(id);
      const login = await requestDeviceCode(id);
      setPending({ ...login, clientId: id });
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'เชื่อม OneDrive ไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  };

  return (
    <KeyboardAvoidingView style={styles.screen} behavior="padding">
      <ScrollView
        contentContainerStyle={[styles.content, { paddingTop: insets.top + 12, paddingBottom: insets.bottom + 28 }]}
        keyboardShouldPersistTaps="handled"
      >
        <Pressable onPress={onClose} hitSlop={8}>
          <Text style={styles.back}>‹  ปิด</Text>
        </Pressable>
        <Text style={styles.title}>เชื่อม OneDrive</Text>
        <Text style={styles.lead}>ล็อกอินด้วยบัญชี Microsoft ที่เป็นเจ้าของไฟล์หนัง แอปขอแค่อ่านไฟล์ ไม่แก้และไม่ลบ</Text>

        {session ? (
          <View style={styles.card}>
            <Text style={styles.label}>เชื่อมอยู่</Text>
            <Text style={styles.account}>{session.displayName}</Text>
            <Pressable
              onPress={() => {
                void signOut();
              }}
            >
              <Text style={styles.disconnect}>เลิกเชื่อม</Text>
            </Pressable>
          </View>
        ) : null}

        {pending ? (
          <View style={styles.card}>
            <Text style={styles.label}>ใส่รหัสนี้ในหน้า Microsoft</Text>
            <Text style={styles.code}>{pending.userCode}</Text>
            <Text style={styles.hint}>กำลังรอการยืนยันจากเบราว์เซอร์</Text>
            <Pressable style={styles.primary} onPress={() => Linking.openURL(pending.verificationUri)}>
              <Text style={styles.primaryText}>เปิดหน้าเว็บ Microsoft</Text>
            </Pressable>
            <Pressable style={styles.secondary} onPress={() => Clipboard.setStringAsync(pending.userCode)}>
              <Text style={styles.secondaryText}>คัดลอกรหัส</Text>
            </Pressable>
            <Pressable onPress={() => setPending(null)}>
              <Text style={styles.cancel}>ยกเลิก</Text>
            </Pressable>
          </View>
        ) : (
          <View style={styles.form}>
            <Text style={styles.label}>Application (client) ID</Text>
            <TextInput
              value={clientId}
              onChangeText={setClientId}
              autoCapitalize="none"
              autoCorrect={false}
              placeholder="00000000-0000-0000-0000-000000000000"
              placeholderTextColor={theme.faint}
              style={styles.input}
            />
            <Text style={styles.section}>สิทธิ์ Microsoft Graph แบบ Delegated</Text>
            <Text style={styles.step}>Files.Read — อ่านไฟล์ใน OneDrive ของบัญชีที่ล็อกอิน</Text>
            <Text style={styles.step}>User.Read — อ่านชื่อบัญชี</Text>
            <Text style={styles.step}>offline_access — ให้แอปอยู่ต่อได้โดยไม่ต้องล็อกอินใหม่ทุกครั้ง</Text>
            <Text style={styles.section}>ตั้งค่าใน Azure</Text>
            <Text style={styles.step}>1. สร้าง App registration แล้วเลือกบัญชีส่วนตัวและที่ทำงาน</Text>
            <Text style={styles.step}>2. เปิด Allow public client flows เป็น Yes</Text>
            <Text style={styles.step}>3. เพิ่มสิทธิ์ Files.Read และ User.Read แล้วนำ Client ID มาวางด้านบน</Text>
            {error ? <Text style={styles.error}>{error}</Text> : null}
            <Pressable style={[styles.primary, !clientReady && styles.disabled]} disabled={!clientReady || busy} onPress={start}>
              {busy ? <ActivityIndicator color={theme.accentInk} /> : <Text style={styles.primaryText}>ล็อกอินด้วย Microsoft</Text>}
            </Pressable>
          </View>
        )}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: theme.bg },
  content: { paddingHorizontal: 24, gap: 16 },
  back: { color: theme.muted, fontFamily: font.medium, fontSize: 16 },
  title: { color: theme.text, fontFamily: font.semibold, fontSize: 34, lineHeight: 38 },
  lead: { color: theme.muted, fontFamily: font.body, fontSize: 16, lineHeight: 24 },
  form: { gap: 8 },
  card: { backgroundColor: theme.raised, borderRadius: 20, gap: 10, padding: 18 },
  label: { color: theme.muted, fontFamily: font.medium, fontSize: 13, marginTop: 6 },
  section: { color: theme.text, fontFamily: font.semibold, fontSize: 15, marginTop: 14 },
  account: { color: theme.text, fontFamily: font.semibold, fontSize: 22 },
  step: { color: theme.faint, fontFamily: font.body, fontSize: 14, lineHeight: 20 },
  hint: { color: theme.faint, fontFamily: font.body, fontSize: 14 },
  input: {
    backgroundColor: theme.raised,
    borderColor: theme.line,
    borderRadius: 14,
    borderWidth: 1,
    color: theme.text,
    fontFamily: font.body,
    fontSize: 15,
    paddingHorizontal: 14,
    paddingVertical: 14,
  },
  code: { color: theme.text, fontFamily: font.semibold, fontSize: 36, letterSpacing: 2 },
  primary: {
    alignItems: 'center',
    backgroundColor: theme.accent,
    borderRadius: 16,
    height: 54,
    justifyContent: 'center',
    marginTop: 12,
  },
  primaryText: { color: theme.accentInk, fontFamily: font.semibold, fontSize: 16 },
  secondary: {
    alignItems: 'center',
    borderColor: theme.line,
    borderRadius: 16,
    borderWidth: 1,
    height: 48,
    justifyContent: 'center',
  },
  secondaryText: { color: theme.text, fontFamily: font.medium, fontSize: 15 },
  cancel: { color: theme.muted, fontFamily: font.medium, textAlign: 'center' },
  disconnect: { color: theme.danger, fontFamily: font.medium, fontSize: 15 },
  disabled: { opacity: 0.4 },
  error: { color: theme.danger, fontFamily: font.medium, fontSize: 14, lineHeight: 20 },
});
