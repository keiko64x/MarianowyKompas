import 'dart:math';

const List<String> kSpiritNames = [
  'Sun Dancer',
  'Spirit Traveler',
  'Peace Keeper',
  'Forest Mystic',
  'Soul Wandering',
  'Sacred Fire',
  'Cosmic Child',
  'Earth Guardian',
  'Moon Walker',
  'Harmony Seeker',
  'Star Nomad',
  'Dream Weaver',
  'Wild Spirit',
  'Light Bearer',
  'Solar Nomad',
  'Healing Tribe',
  'Mystic Pilgrim',
  'Ancient Flame',
  'Astral Voyager',
  'Zen Wanderer',
];

/// Random English spirit name + 4-digit suffix, e.g. "Forest Mystic 4821".
String randomSpiritProfileName([Random? random]) {
  final rng = random ?? Random();
  final name = kSpiritNames[rng.nextInt(kSpiritNames.length)];
  final digits = rng.nextInt(9000) + 1000; // 1000–9999
  return '$name $digits';
}
