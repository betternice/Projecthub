import { useEffect, useState } from 'react';
import { ActivityIndicator, Image, Pressable, ScrollView, StyleSheet, Text, View, useWindowDimensions } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Poster } from '../components/Poster';
import { useAuth } from '../auth/AuthContext';
import { formatBytes, formatClock, formatRuntime, presentTitle } from '../format';
import { lookupDetail, lookupMedia, type CastMember, type MediaDetail, type MediaMatch } from '../metadata/tmdb';
import { getPlaybackUrl, type DriveItem } from '../onedrive/graph';
import { font, theme } from '../theme';

type DetailProps = {
  item: DriveItem;
  match: MediaMatch | null;
  onBack: () => void;
  onPlay: (title: string, url: string) => void;
};

export function DetailScreen({ item, match, onBack, onPlay }: DetailProps) {
  const insets = useSafeAreaInsets();
  const { width } = useWindowDimensions();
  const { tmdbKey, getToken } = useAuth();
  const parsed = presentTitle(item.name);
  const [detail, setDetail] = useState<MediaDetail | null>(
    match ? { ...match, runtime: null, cast: [], genres: [], director: null } : null,
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      const found = match ?? (await lookupMedia(item.name, tmdbKey));
      if (!found || cancelled) return;
      const next = await lookupDetail(found, tmdbKey);
      if (!cancelled) setDetail(next);
    };
    void load();
    return () => {
      cancelled = true;
    };
  }, [item.name, match, tmdbKey]);

  const title = detail?.title || parsed.title;
  const year = detail?.year || parsed.year;
  const runtime = formatRuntime(detail?.runtime) || formatClock(item.video?.duration);
  const facts = [
    year,
    runtime,
    detail?.director ? detail.director : null,
    detail?.rating ? `★ ${detail.rating.toFixed(1)}` : null,
    ...(detail?.genres ?? []),
  ].filter(Boolean);
  const poster = detail?.posterUrl ?? item.thumbnails?.[0]?.large?.url ?? item.thumbnails?.[0]?.medium?.url;
  const artwork = detail?.backdropUrl ?? poster;

  const play = async () => {
    setBusy(true);
    setError(null);
    try {
      const token = await getToken();
      const url = await getPlaybackUrl(token, item.id);
      onPlay(title, url);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'เล่นไฟล์นี้ไม่ได้');
    } finally {
      setBusy(false);
    }
  };

  return (
    <View style={styles.screen}>
      <ScrollView contentContainerStyle={{ paddingBottom: insets.bottom + 36 }}>
        <View style={[styles.hero, { height: width * 0.72 }]}>
          {artwork ? <Image source={{ uri: artwork }} style={styles.artwork} /> : <View style={styles.artwork} />}
          <LinearGradient colors={['rgba(0,0,0,0.28)', 'rgba(0,0,0,0.08)', '#000000']} locations={[0, 0.42, 1]} style={styles.fade} />
          <Pressable style={[styles.back, { top: insets.top + 8 }]} onPress={onBack} hitSlop={10}>
            <Text style={styles.backText}>‹</Text>
          </Pressable>
        </View>

        <View style={styles.identity}>
          <Poster uri={poster} title={title} seed={item.id} style={styles.poster} />
          <View style={styles.identityText}>
            <Text style={styles.title}>{title}</Text>
            {facts.length > 0 ? <Text style={styles.facts}>{facts.join('   ·   ')}</Text> : null}
          </View>
        </View>

        <View style={styles.body}>
          <Pressable style={styles.play} onPress={play} disabled={busy}>
            {busy ? (
              <ActivityIndicator color="#000" />
            ) : (
              <Text style={styles.playText}>▶   เล่น</Text>
            )}
          </Pressable>
          {error ? <Text style={styles.error}>{error}</Text> : null}
          {detail?.overview ? <Text style={styles.overview}>{detail.overview}</Text> : null}
          {detail?.cast?.length ? (
            <View>
              <Text style={styles.section}>นักแสดง</Text>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.castRow}>
                {detail.cast.map((person) => (
                  <CastCard key={`${person.name}-${person.character}`} person={person} />
                ))}
              </ScrollView>
            </View>
          ) : null}
          <View style={styles.file}>
            <Text style={styles.section}>ไฟล์</Text>
            <Text style={styles.filename}>{item.name}</Text>
            <Text style={styles.fileMeta}>{formatBytes(item.size) ?? 'OneDrive'}</Text>
          </View>
        </View>
      </ScrollView>
    </View>
  );
}

function CastCard({ person }: { person: CastMember }) {
  return (
    <View style={styles.cast}>
      {person.profileUrl ? <Image source={{ uri: person.profileUrl }} style={styles.avatar} /> : <View style={styles.avatar} />}
      <Text style={styles.castName} numberOfLines={2}>
        {person.name}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#000' },
  hero: { justifyContent: 'flex-end' },
  artwork: { ...StyleSheet.absoluteFill, backgroundColor: '#141416' },
  fade: { ...StyleSheet.absoluteFill },
  back: { left: 16, position: 'absolute' },
  backText: { color: '#fff', fontFamily: font.medium, fontSize: 34, lineHeight: 36 },
  identity: { flexDirection: 'row', gap: 14, marginTop: -72, paddingHorizontal: 20 },
  poster: { height: 156, width: 104 },
  identityText: { flex: 1, justifyContent: 'flex-end', paddingBottom: 4 },
  title: { color: '#fff', fontFamily: font.semibold, fontSize: 28, lineHeight: 32 },
  facts: { color: 'rgba(255,255,255,0.78)', fontFamily: font.medium, fontSize: 13, lineHeight: 18, marginTop: 8 },
  body: { gap: 18, paddingHorizontal: 20, paddingTop: 18 },
  play: {
    alignItems: 'center',
    backgroundColor: '#fff',
    borderRadius: 12,
    height: 50,
    justifyContent: 'center',
  },
  playText: { color: '#000', fontFamily: font.semibold, fontSize: 17 },
  error: { color: theme.danger, fontFamily: font.medium, fontSize: 14, lineHeight: 20 },
  overview: { color: '#D1D1D6', fontFamily: font.body, fontSize: 15, lineHeight: 23 },
  section: { color: theme.muted, fontFamily: font.medium, fontSize: 13, marginBottom: 12 },
  castRow: { gap: 14 },
  cast: { width: 76 },
  avatar: { backgroundColor: theme.raised, borderRadius: 38, height: 76, width: 76 },
  castName: { color: theme.text, fontFamily: font.medium, fontSize: 12, lineHeight: 16, marginTop: 8 },
  file: { paddingTop: 4 },
  filename: { color: theme.text, fontFamily: font.medium, fontSize: 14, lineHeight: 20 },
  fileMeta: { color: theme.faint, fontFamily: font.body, fontSize: 13, marginTop: 4 },
});
