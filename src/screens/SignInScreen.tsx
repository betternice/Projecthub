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

export function SignInScreen() {
  const insets = useSafeAreaInsets();
  const { savedClientId, tmdbKey, saveClientId, saveSession, setTmdbKey } = useAuth();
  const [clientId, setClientId] = useState(savedClientId);
  const [tmdbDraft, setTmdbDraft] = useState(tmdbKey ?? '');
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
          return;
        }
        setPending(null);
        setError(result.status === 'expired' ? 'รหัสหมดอายุแล้ว ลองเข้าสู่ระบบใหม่' : 'ยกเลิกการเข้าสู่ระบบ');
      } catch (cause) {
        if (!cancelled) {
          setPending(null);
          setError(cause instanceof Error ? cause.message : 'เข้าสู่ระบบไม่สำเร็จ');
        }
      }
    };

    timer = setTimeout(tick, wait * 1000);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [pending, saveSession]);

  const start = async () => {
    const id = clientId.trim();
    setError(null);
    setBusy(true);
    try {
      await saveClientId(id);
      await setTmdbKey(tmdbDraft);
      const login = await requestDeviceCode(id);
      setPending({ ...login, clientId: id });
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'เข้าสู่ระบบไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  };

  return (
    <KeyboardAvoidingView style={styles.screen} behavior="padding">
      <ScrollView
        contentContainerStyle={[styles.content, { paddingTop: insets.top + 28, paddingBottom: insets.bottom + 28 }]}
        keyboardShouldPersistTaps="handled"
      >
        <Text style={styles.eyebrow}>OneDrive</Text>
        <Text style={styles.title}>Movie{'\n'}Collection</Text>
        <Text style={styles.lead}>คลังหนังจากไฟล์ใน OneDrive พร้อมปก รายละเอียด และปุ่มเล่น</Text>

        {pending ? (
          <View style={styles.codeCard}>
            <Text style={styles.codeLabel}>ใส่รหัสนี้ในหน้า Microsoft</Text>
            <Text style={styles.code}>{pending.userCode}</Text>
            <Text style={styles.codeHint}>กำลังรอการยืนยันจากเบราว์เซอร์</Text>
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
            <Text style={styles.label}>TMDB API key ไม่จำเป็น</Text>
            <TextInput
              value={tmdbDraft}
              onChangeText={setTmdbDraft}
              autoCapitalize="none"
              autoCorrect={false}
              placeholder="เว้นไว้ได้ ปกและเรื่องย่อมาให้อยู่แล้ว"
              placeholderTextColor={theme.faint}
              style={styles.input}
            />
            <View style={styles.steps}>
              <Text style={styles.step}>1. เปิด portal.azure.com แล้วสร้าง App registration ชื่อ Movie Collection</Text>
              <Text style={styles.step}>2. เลือกบัญชี Microsoft ส่วนตัวและที่ทำงาน</Text>
              <Text style={styles.step}>3. เปิด Authentication แล้วตั้ง Allow public client flows เป็น Yes</Text>
              <Text style={styles.step}>4. เพิ่มสิทธิ์ Microsoft Graph แบบ Delegated ชื่อ Files.Read</Text>
              <Text style={styles.step}>5. นำ Application (client) ID มาวางด้านบน</Text>
            </View>
            {error ? <Text style={styles.error}>{error}</Text> : null}
            <Pressable style={[styles.primary, !clientReady && styles.disabled]} disabled={!clientReady || busy} onPress={start}>
              {busy ? <ActivityIndicator color={theme.accentInk} /> : <Text style={styles.primaryText}>เข้าสู่ระบบด้วย Microsoft</Text>}
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
  eyebrow: {
    color: theme.muted,
    fontFamily: font.medium,
    fontSize: 15,
  },
  title: {
    color: theme.text,
    fontFamily: font.semibold,
    fontSize: 40,
    lineHeight: 44,
  },
  lead: {
    color: theme.muted,
    fontFamily: font.body,
    fontSize: 16,
    lineHeight: 24,
    marginBottom: 8,
  },
  form: { gap: 10 },
  label: { color: theme.muted, fontFamily: font.medium, fontSize: 13, marginTop: 8 },
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
  steps: { gap: 6, marginTop: 8 },
  step: { color: theme.faint, fontFamily: font.body, fontSize: 13, lineHeight: 19 },
  codeCard: {
    backgroundColor: theme.raised,
    borderRadius: 24,
    gap: 12,
    padding: 20,
  },
  codeLabel: { color: theme.muted, fontFamily: font.medium, fontSize: 14 },
  code: {
    color: theme.text,
    fontFamily: font.semibold,
    fontSize: 36,
    letterSpacing: 2,
  },
  codeHint: { color: theme.faint, fontFamily: font.body, fontSize: 14 },
  primary: {
    alignItems: 'center',
    backgroundColor: theme.accent,
    borderRadius: 16,
    height: 54,
    justifyContent: 'center',
    marginTop: 8,
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
  disabled: { opacity: 0.4 },
  error: { color: theme.danger, fontFamily: font.medium, fontSize: 14, lineHeight: 20 },
});
