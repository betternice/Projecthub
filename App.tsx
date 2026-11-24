import { useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { useFonts, Fraunces_500Medium_Italic, Fraunces_600SemiBold } from '@expo-google-fonts/fraunces';
import { Outfit_400Regular, Outfit_500Medium, Outfit_600SemiBold } from '@expo-google-fonts/outfit';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { AuthProvider, useAuth } from './src/auth/AuthContext';
import { font, theme } from './src/theme';
import type { MediaMatch } from './src/metadata/tmdb';
import type { DriveItem } from './src/onedrive/graph';
import { DetailScreen } from './src/screens/DetailScreen';
import { LibraryScreen } from './src/screens/LibraryScreen';
import { PlayerScreen } from './src/screens/PlayerScreen';
import { SignInScreen } from './src/screens/SignInScreen';

type DetailRoute = { name: 'detail'; item: DriveItem; match: MediaMatch | null };
type PlayerRoute = { name: 'player'; title: string; url: string };

export default function App() {
  const [loaded] = useFonts({
    Fraunces_600SemiBold,
    Fraunces_500Medium_Italic,
    Outfit_400Regular,
    Outfit_500Medium,
    Outfit_600SemiBold,
  });

  if (!loaded) return null;

  return (
    <SafeAreaProvider>
      <AuthProvider>
        <StatusBar style="light" />
        <Root />
      </AuthProvider>
    </SafeAreaProvider>
  );
}

function Root() {
  const { ready, session } = useAuth();
  const [detail, setDetail] = useState<DetailRoute | null>(null);
  const [player, setPlayer] = useState<PlayerRoute | null>(null);

  if (!ready) {
    return (
      <View style={styles.boot}>
        <Text style={styles.bootText}>Movie Collection</Text>
      </View>
    );
  }

  if (!session) return <SignInScreen />;
  if (player) return <PlayerScreen title={player.title} url={player.url} onClose={() => setPlayer(null)} />;
  if (detail) {
    return (
      <DetailScreen
        item={detail.item}
        match={detail.match}
        onBack={() => setDetail(null)}
        onPlay={(title, url) => setPlayer({ name: 'player', title, url })}
      />
    );
  }

  return <LibraryScreen onOpen={(item, match) => setDetail({ name: 'detail', item, match })} />;
}

const styles = StyleSheet.create({
  boot: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: theme.bg },
  bootText: { color: theme.text, fontFamily: font.display, fontSize: 28 },
});
