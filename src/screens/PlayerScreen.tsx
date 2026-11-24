import { StyleSheet, Text, View, Pressable } from 'react-native';
import { useEvent } from 'expo';
import { useVideoPlayer, VideoView } from 'expo-video';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { font, theme } from '../theme';

type PlayerProps = {
  title: string;
  url: string;
  onClose: () => void;
};

export function PlayerScreen({ title, url, onClose }: PlayerProps) {
  const insets = useSafeAreaInsets();
  const player = useVideoPlayer(url, (instance) => {
    instance.play();
  });
  const status = useEvent(player, 'statusChange', { status: player.status });

  return (
    <View style={styles.screen}>
      <VideoView
        player={player}
        style={styles.video}
        nativeControls
        contentFit="contain"
        fullscreenOptions={{ enable: true }}
      />
      <View style={[styles.top, { paddingTop: insets.top + 8 }]}>
        <Pressable style={styles.close} onPress={onClose}>
          <Text style={styles.closeText}>ปิด</Text>
        </Pressable>
        <Text style={styles.title} numberOfLines={1}>
          {title}
        </Text>
      </View>
      {status.status === 'error' ? (
        <View style={styles.errorWrap}>
          <Text style={styles.error}>เครื่องนี้เปิดไฟล์นี้ไม่ได้ ตัวเล่นของ Android รองรับ mp4 และ mkv ส่วนใหญ่</Text>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#000' },
  video: { flex: 1 },
  top: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 16,
    paddingBottom: 12,
  },
  close: {
    backgroundColor: 'rgba(0,0,0,0.55)',
    borderRadius: 999,
    paddingHorizontal: 14,
    paddingVertical: 8,
  },
  closeText: { color: '#fff', fontFamily: font.medium, fontSize: 14 },
  title: { color: '#fff', flex: 1, fontFamily: font.medium, fontSize: 15 },
  errorWrap: {
    position: 'absolute',
    left: 20,
    right: 20,
    bottom: 40,
    backgroundColor: 'rgba(0,0,0,0.78)',
    borderRadius: 16,
    padding: 16,
  },
  error: { color: theme.text, fontFamily: font.body, fontSize: 14, lineHeight: 21 },
});
