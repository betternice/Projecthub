export const theme = {
  bg: '#000000',
  raised: '#1C1C1E',
  line: 'rgba(255, 255, 255, 0.14)',
  text: '#FFFFFF',
  muted: '#A1A1A6',
  faint: '#6E6E73',
  accent: '#FFFFFF',
  accentInk: '#000000',
  danger: '#FF453A',
};

export const font = {
  display: 'Fraunces_600SemiBold',
  displayItalic: 'Fraunces_500Medium_Italic',
  body: 'Outfit_400Regular',
  medium: 'Outfit_500Medium',
  semibold: 'Outfit_600SemiBold',
};

const posterColors = ['#1C1C1E', '#2C2C2E', '#1A2330', '#242426', '#1E2422', '#2A2430'];

export function posterColor(seed: string): string {
  let hash = 0;
  for (let i = 0; i < seed.length; i += 1) hash = (hash * 31 + seed.charCodeAt(i)) >>> 0;
  return posterColors[hash % posterColors.length];
}
