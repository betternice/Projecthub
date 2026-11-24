import { useState } from 'react';
import { Image, StyleSheet, Text, View, type StyleProp, type ViewStyle } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';

import { font, posterColor, theme } from '../theme';

type PosterProps = {
  uri?: string | null;
  title: string;
  seed: string;
  style?: StyleProp<ViewStyle>;
};

export function Poster({ uri, title, seed, style }: PosterProps) {
  const [failed, setFailed] = useState(false);
  const showImage = Boolean(uri) && !failed;

  return (
    <View style={[styles.frame, style]}>
      {showImage ? (
        <Image source={{ uri: uri ?? undefined }} style={styles.image} onError={() => setFailed(true)} />
      ) : (
        <LinearGradient colors={[posterColor(seed), '#12110E']} style={styles.fallback}>
          <Text style={styles.fallbackTitle} numberOfLines={4}>
            {title}
          </Text>
        </LinearGradient>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  frame: {
    overflow: 'hidden',
    borderRadius: 6,
    backgroundColor: theme.raised,
  },
  image: {
    width: '100%',
    height: '100%',
  },
  fallback: {
    flex: 1,
    justifyContent: 'flex-end',
    padding: 8,
  },
  fallbackTitle: {
    color: theme.text,
    fontFamily: font.semibold,
    fontSize: 13,
    lineHeight: 16,
  },
});
