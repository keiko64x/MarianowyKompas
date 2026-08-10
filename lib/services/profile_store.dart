import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/peer.dart';
import '../models/user_profile.dart';

const _profileKey = 'medicine_compass_profile_v1';
const _peersCacheKey = 'medicine_compass_peers_cache_v1';
const _themeKey = 'medicine_compass_theme';
const _skipWelcomeKey = 'medicine_compass_skip_welcome';

class ProfileStore {
  Future<UserProfile?> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    if (raw == null || raw.isEmpty) return null;
    return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  Future<List<Peer>> loadPeersCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_peersCacheKey);
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((item) => Peer.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> savePeersCache(List<Peer> peers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _peersCacheKey,
      jsonEncode(peers.map((p) => p.toJson()).toList()),
    );
  }

  Future<bool> loadSkipWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_skipWelcomeKey) ?? false;
  }

  Future<void> setSkipWelcome(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_skipWelcomeKey, value);
  }

  Future<String?> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeKey);
  }

  Future<void> saveTheme(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, value);
  }
}
