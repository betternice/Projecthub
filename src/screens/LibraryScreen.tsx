import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Image,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  useWindowDimensions,
  View,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import * as SecureStore from 'expo-secure-store';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Poster } from '../components/Poster';
import { ConnectSheet } from './ConnectSheet';
import { useAuth } from '../auth/AuthContext';
import { presentTitle } from '../format';
import { lookupMedia, type MediaMatch } from '../metadata/tmdb';
import { isVideoFile, listChildren, type DriveItem } from '../onedrive/graph';
import { font, theme } from '../theme';

export type FolderCrumb = { id: string; name: string };

type LibraryProps = {
  onOpen: (item: DriveItem, match: MediaMatch | null) => void;
};

type LibraryMovie = {
  item: DriveItem;
  match: MediaMatch | null;
  title: string;
  year: string | null;
};

export function LibraryScreen({ onOpen }: LibraryProps) {
  const insets = useSafeAreaInsets();
  const { width } = useWindowDimensions();
  const { session, tmdbKey, setTmdbKey, getToken } = useAuth();
  const [folders, setFolders] = useState<FolderCrumb[] | null>(null);
  const [items, setItems] = useState<DriveItem[]>([]);
  const [matches, setMatches] = useState<Record<string, MediaMatch | null>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [connectOpen, setConnectOpen] = useState(false);
  const [tmdbDraft, setTmdbDraft] = useState(tmdbKey ?? '');
  const [reloadKey, setReloadKey] = useState(0);

  const current = folders?.[folders.length - 1];
  const videos = items.filter(isVideoFile).sort((a, b) => a.name.localeCompare(b.name, 'th'));
  const videoKey = videos.map((video) => video.id).join('|');
  const subfolders = items.filter((item) => item.folder).sort((a, b) => a.name.localeCompare(b.name, 'th'));
  const gap = 8;
  const cardWidth = (width - 16 * 2 - gap * 2) / 3;
  const movies: LibraryMovie[] = videos
    .map((item) => {
      const match = matches[item.id] ?? null;
      const parsed = presentTitle(item.name);
      return {
        item,
        match,
        title: match?.title || parsed.title,
        year: match?.year || parsed.year,
      };
    })
    .sort((a, b) => a.title.localeCompare(b.title, 'th'));
  const featured = movies.filter((movie) => movie.match?.backdropUrl).slice(0, 8);
  const screenTitle = !current || current.id === 'root' ? 'Movies' : current.name;
  const parent = folders && folders.length > 1 ? folders[folders.length - 2] : null;

  useEffect(() => {
    let cancelled = false;
    SecureStore.getItemAsync('folders').then((raw) => {
      if (cancelled) return;
      if (!raw) {
        setFolders([{ id: 'root', name: 'OneDrive' }]);
        return;
      }
      try {
        const parsed = JSON.parse(raw) as FolderCrumb[];
        setFolders(parsed.length > 0 ? parsed : [{ id: 'root', name: 'OneDrive' }]);
      } catch {
        setFolders([{ id: 'root', name: 'OneDrive' }]);
      }
    });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!current) return undefined;
    let cancelled = false;
    const load = async () => {
      if (!session) {
        setLoading(false);
        setError(null);
        setItems([]);
        setMatches({});
        return;
      }
      setLoading(true);
      setError(null);
      setItems([]);
      setMatches({});
      try {
        const token = await getToken();
        const next = await listChildren(token, current.id);
        if (!cancelled) setItems(next);
      } catch (cause) {
        if (!cancelled) setError(cause instanceof Error ? cause.message : 'โหลดไฟล์จาก OneDrive ไม่สำเร็จ');
      } finally {
        if (!cancelled) setLoading(false);
      }
    };
    void load();
    return () => {
      cancelled = true;
    };
  }, [current, getToken, reloadKey, session]);

  useEffect(() => {
    if (videoKey.length === 0) return undefined;
    let cancelled = false;
    const queue = videos;
    let index = 0;

    const worker = async () => {
      while (index < queue.length) {
        const item = queue[index];
        index += 1;
        try {
          const match = await lookupMedia(item.name, tmdbKey);
          if (!cancelled) setMatches((prev) => ({ ...prev, [item.id]: match }));
        } catch {
          if (!cancelled) setMatches((prev) => ({ ...prev, [item.id]: null }));
        }
      }
    };

    void Promise.all([worker(), worker(), worker()]);
    return () => {
      cancelled = true;
    };
  }, [tmdbKey, videoKey]);

  const remember = (next: FolderCrumb[]) => {
    setFolders(next);
    void SecureStore.setItemAsync('folders', JSON.stringify(next));
  };

  return (
    <View style={styles.screen}>
      <FlatList
        data={movies}
        keyExtractor={(movie) => movie.item.id}
        numColumns={3}
        columnWrapperStyle={movies.length > 0 ? styles.columns : undefined}
        contentContainerStyle={{ paddingTop: insets.top + 8, paddingBottom: insets.bottom + 28, paddingHorizontal: 16 }}
        refreshing={loading && items.length > 0}
        onRefresh={() => setReloadKey((value) => value + 1)}
        ListHeaderComponent={
          <View style={styles.header}>
            {parent ? (
              <Pressable onPress={() => remember(folders!.slice(0, -1))} hitSlop={8}>
                <Text style={styles.back}>‹  {parent.name}</Text>
              </Pressable>
            ) : null}
            <View style={styles.titleRow}>
              <Text style={styles.title} numberOfLines={2}>
                {screenTitle}
              </Text>
              <Pressable onPress={() => setSettingsOpen(true)} hitSlop={10} style={styles.moreButton}>
                <Text style={styles.more}>•••</Text>
              </Pressable>
            </View>
            {movies.length > 0 ? <Text style={styles.count}>{movies.length} เรื่อง</Text> : null}
            {error ? <Text style={styles.error}>{error}</Text> : null}
            {featured.length > 0 ? (
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.featuredRow}>
                {featured.map((movie) => (
                  <Pressable key={movie.item.id} style={styles.featured} onPress={() => onOpen(movie.item, movie.match)}>
                    <Image source={{ uri: movie.match?.backdropUrl ?? undefined }} style={styles.featuredImage} />
                    <LinearGradient colors={['transparent', 'rgba(0,0,0,0.88)']} style={styles.featuredFade} />
                    <View style={styles.featuredText}>
                      <Text style={styles.featuredTitle} numberOfLines={1}>
                        {movie.title}
                      </Text>
                      {movie.year ? <Text style={styles.featuredYear}>{movie.year}</Text> : null}
                    </View>
                  </Pressable>
                ))}
              </ScrollView>
            ) : null}
            {subfolders.map((folder) => (
              <Pressable
                key={folder.id}
                style={styles.folderRow}
                onPress={() => remember([...(folders ?? []), { id: folder.id, name: folder.name }])}
              >
                <View style={styles.folderMark}>
                  <Text style={styles.folderMarkText}>▣</Text>
                </View>
                <Text style={styles.folderName} numberOfLines={1}>
                  {folder.name}
                </Text>
                <Text style={styles.chevron}>›</Text>
              </Pressable>
            ))}
          </View>
        }
        ListEmptyComponent={
          loading ? (
            <ActivityIndicator color={theme.text} style={styles.spinner} />
          ) : subfolders.length > 0 ? undefined : (
            <View style={styles.emptyWrap}>
              <Text style={styles.empty}>{session ? 'ยังไม่มีไฟล์วิดีโอในโฟลเดอร์นี้' : 'คลังยังว่าง'}</Text>
              {session ? null : (
                <Pressable style={styles.connectButton} onPress={() => setConnectOpen(true)}>
                  <Text style={styles.connectButtonText}>เชื่อม OneDrive</Text>
                </Pressable>
              )}
            </View>
          )
        }
        renderItem={({ item: movie }) => {
          const frame = movie.item.thumbnails?.[0]?.large?.url ?? movie.item.thumbnails?.[0]?.medium?.url;
          return (
            <Pressable style={{ width: cardWidth }} onPress={() => onOpen(movie.item, movie.match)}>
              <Poster
                uri={movie.match?.posterUrl ?? frame}
                title={movie.title}
                seed={movie.item.id}
                style={{ width: cardWidth, height: cardWidth * 1.5 }}
              />
              <Text style={styles.cardTitle} numberOfLines={2}>
                {movie.title}
              </Text>
              <Text style={styles.cardYear}>{movie.year ?? ''}</Text>
            </Pressable>
          );
        }}
      />
      <Modal visible={settingsOpen} transparent animationType="fade" onRequestClose={() => setSettingsOpen(false)}>
        <View style={styles.modalBackdrop}>
          <Pressable style={StyleSheet.absoluteFill} onPress={() => setSettingsOpen(false)} />
          <View style={styles.modal}>
            <Text style={styles.modalTitle}>ตั้งค่า</Text>
            <Pressable
              style={styles.menuRow}
              onPress={() => {
                setSettingsOpen(false);
                setConnectOpen(true);
              }}
            >
              <View style={styles.menuCopy}>
                <Text style={styles.menuLabel}>เชื่อม OneDrive</Text>
                <Text style={styles.menuHint}>{session ? session.displayName : 'ยังไม่ได้เชื่อม'}</Text>
              </View>
              <Text style={styles.chevron}>›</Text>
            </Pressable>
            <Text style={styles.modalTitle}>ปกและรายละเอียด</Text>
            <Text style={styles.modalBody}>แอปดึงปกและเรื่องย่อให้อยู่แล้ว ใส่ API key จาก themoviedb.org เมื่ออยากได้รูปนักแสดงเพิ่ม</Text>
            <TextInput
              value={tmdbDraft}
              onChangeText={setTmdbDraft}
              autoCapitalize="none"
              autoCorrect={false}
              placeholder="TMDB API key"
              placeholderTextColor={theme.faint}
              style={styles.input}
            />
            <Pressable
              style={styles.save}
              onPress={() => {
                void setTmdbKey(tmdbDraft);
                setSettingsOpen(false);
              }}
            >
              <Text style={styles.saveText}>บันทึก</Text>
            </Pressable>
          </View>
        </View>
      </Modal>
      <Modal visible={connectOpen} animationType="slide" onRequestClose={() => setConnectOpen(false)}>
        <ConnectSheet onClose={() => setConnectOpen(false)} />
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: theme.bg },
  header: { gap: 10, marginBottom: 14 },
  back: { color: theme.muted, fontFamily: font.medium, fontSize: 16 },
  titleRow: { alignItems: 'flex-start', flexDirection: 'row', justifyContent: 'space-between' },
  title: { color: theme.text, flex: 1, fontFamily: font.semibold, fontSize: 34, lineHeight: 38 },
  moreButton: { marginRight: 56, marginTop: 6 },
  more: { color: theme.text, fontFamily: font.semibold, fontSize: 20, letterSpacing: 2 },
  count: { color: theme.muted, fontFamily: font.body, fontSize: 13 },
  error: { color: theme.danger, fontFamily: font.medium, fontSize: 14 },
  featuredRow: { gap: 10, paddingVertical: 6 },
  featured: { borderRadius: 10, height: 132, overflow: 'hidden', width: 236 },
  featuredImage: { ...StyleSheet.absoluteFill, backgroundColor: theme.raised },
  featuredFade: { position: 'absolute', left: 0, right: 0, bottom: 0, height: 78 },
  featuredText: { position: 'absolute', left: 12, right: 12, bottom: 10 },
  featuredTitle: { color: '#fff', fontFamily: font.semibold, fontSize: 16 },
  featuredYear: { color: 'rgba(255,255,255,0.75)', fontFamily: font.body, fontSize: 12, marginTop: 2 },
  folderRow: { alignItems: 'center', flexDirection: 'row', gap: 12, paddingVertical: 8 },
  folderMark: {
    alignItems: 'center',
    backgroundColor: theme.raised,
    borderRadius: 8,
    height: 36,
    justifyContent: 'center',
    width: 36,
  },
  folderMarkText: { color: theme.muted, fontSize: 16 },
  folderName: { color: theme.text, flex: 1, fontFamily: font.medium, fontSize: 16 },
  chevron: { color: theme.faint, fontSize: 22 },
  columns: { gap: 8 },
  cardTitle: { color: theme.text, fontFamily: font.medium, fontSize: 12, lineHeight: 15, marginTop: 6 },
  cardYear: { color: theme.faint, fontFamily: font.body, fontSize: 11, height: 16, marginBottom: 12 },
  spinner: { marginTop: 36 },
  emptyWrap: { gap: 16, marginTop: 8 },
  empty: { color: theme.muted, fontFamily: font.body, fontSize: 15, lineHeight: 22 },
  connectButton: {
    alignItems: 'center',
    alignSelf: 'flex-start',
    backgroundColor: theme.text,
    borderRadius: 12,
    height: 44,
    justifyContent: 'center',
    paddingHorizontal: 16,
  },
  connectButtonText: { color: '#000', fontFamily: font.semibold, fontSize: 15 },
  menuRow: { alignItems: 'center', flexDirection: 'row', gap: 12, paddingVertical: 4 },
  menuCopy: { flex: 1, gap: 2 },
  menuLabel: { color: theme.text, fontFamily: font.semibold, fontSize: 16 },
  menuHint: { color: theme.muted, fontFamily: font.body, fontSize: 13 },
  modalBackdrop: { backgroundColor: 'rgba(0,0,0,0.62)', flex: 1, justifyContent: 'flex-end' },
  modal: { backgroundColor: '#141416', borderTopLeftRadius: 18, borderTopRightRadius: 18, gap: 12, padding: 22 },
  modalTitle: { color: theme.text, fontFamily: font.semibold, fontSize: 22 },
  modalBody: { color: theme.muted, fontFamily: font.body, fontSize: 14, lineHeight: 21 },
  input: {
    borderColor: theme.line,
    borderRadius: 12,
    borderWidth: 1,
    color: theme.text,
    fontFamily: font.body,
    paddingHorizontal: 14,
    paddingVertical: 14,
  },
  save: { alignItems: 'center', backgroundColor: theme.text, borderRadius: 12, height: 50, justifyContent: 'center' },
  saveText: { color: '#000', fontFamily: font.semibold, fontSize: 16 },
});
