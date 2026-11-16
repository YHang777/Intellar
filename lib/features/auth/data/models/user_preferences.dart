class DesignPreferences {
  const DesignPreferences({
    this.styles = const [],
    this.colours = const [],
    this.materials = const [],
    this.ecoFriendly = false,
    this.notes = '',
  });

  static const styleOptions = [
    'Modern',
    'Scandinavian',
    'Minimalist',
    'Japandi',
    'Industrial',
    'Classic',
    'Bohemian',
    'Mid-century',
    'Tropical',
  ];
  static const colourOptions = [
    'Warm neutrals',
    'Cool greys',
    'Earthy tones',
    'Monochrome',
    'Pastels',
    'Bold colours',
  ];
  static const materialOptions = [
    'Wood',
    'Rattan',
    'Marble',
    'Metal',
    'Fabric',
    'Leather',
    'Glass',
  ];
  static const maxPerGroup = 6;
  static const maxNotes = 200;

  final List<String> styles;
  final List<String> colours;
  final List<String> materials;
  final bool ecoFriendly;
  final String notes;

  bool get isEmpty =>
      styles.isEmpty &&
      colours.isEmpty &&
      materials.isEmpty &&
      !ecoFriendly &&
      notes.trim().isEmpty;

  factory DesignPreferences.fromMap(Object? raw) {
    if (raw is! Map) return const DesignPreferences();
    List<String> list(Object? v) => v is List
        ? v
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .take(maxPerGroup)
            .toList()
        : const [];
    final notes = raw['notes'];
    return DesignPreferences(
      styles: list(raw['styles']),
      colours: list(raw['colours']),
      materials: list(raw['materials']),
      ecoFriendly: raw['ecoFriendly'] == true,
      notes: notes is String ? notes.trim() : '',
    );
  }

  Map<String, Object?> toMap() => {
        'styles': styles,
        'colours': colours,
        'materials': materials,
        'ecoFriendly': ecoFriendly,
        'notes': notes,
      };

  Map<String, Object?>? toChatJson() {
    if (isEmpty) return null;
    String clip(String s, int n) => s.length <= n ? s : s.substring(0, n);
    final trimmedNotes = notes.trim();
    return {
      if (styles.isNotEmpty) 'styles': [for (final s in styles) clip(s, 40)],
      if (colours.isNotEmpty) 'colours': [for (final s in colours) clip(s, 40)],
      if (materials.isNotEmpty)
        'materials': [for (final s in materials) clip(s, 40)],
      if (ecoFriendly) 'ecoFriendly': true,
      if (trimmedNotes.isNotEmpty) 'notes': clip(trimmedNotes, maxNotes),
    };
  }

  DesignPreferences copyWith({
    List<String>? styles,
    List<String>? colours,
    List<String>? materials,
    bool? ecoFriendly,
    String? notes,
  }) =>
      DesignPreferences(
        styles: styles ?? this.styles,
        colours: colours ?? this.colours,
        materials: materials ?? this.materials,
        ecoFriendly: ecoFriendly ?? this.ecoFriendly,
        notes: notes ?? this.notes,
      );
}

class NotificationSettings {
  const NotificationSettings({
    this.orderUpdates = true,
    this.promotions = true,
    this.recommendations = true,
  });

  final bool orderUpdates;
  final bool promotions;
  final bool recommendations;

  factory NotificationSettings.fromMap(Object? raw) {
    if (raw is! Map) return const NotificationSettings();
    return NotificationSettings(
      orderUpdates: raw['orderUpdates'] != false,
      promotions: raw['promotions'] != false,
      recommendations: raw['recommendations'] != false,
    );
  }

  Map<String, Object?> toMap() => {
        'orderUpdates': orderUpdates,
        'promotions': promotions,
        'recommendations': recommendations,
      };

  NotificationSettings copyWith({
    bool? orderUpdates,
    bool? promotions,
    bool? recommendations,
  }) =>
      NotificationSettings(
        orderUpdates: orderUpdates ?? this.orderUpdates,
        promotions: promotions ?? this.promotions,
        recommendations: recommendations ?? this.recommendations,
      );
}

class PrivacySettings {
  const PrivacySettings({
    this.personalisedRecommendations = true,
    this.shareDesignsWithAssistant = true,
  });

  final bool personalisedRecommendations;
  final bool shareDesignsWithAssistant;

  factory PrivacySettings.fromMap(Object? raw) {
    if (raw is! Map) return const PrivacySettings();
    return PrivacySettings(
      personalisedRecommendations: raw['personalisedRecommendations'] != false,
      shareDesignsWithAssistant: raw['shareDesignsWithAssistant'] != false,
    );
  }

  Map<String, Object?> toMap() => {
        'personalisedRecommendations': personalisedRecommendations,
        'shareDesignsWithAssistant': shareDesignsWithAssistant,
      };

  PrivacySettings copyWith({
    bool? personalisedRecommendations,
    bool? shareDesignsWithAssistant,
  }) =>
      PrivacySettings(
        personalisedRecommendations:
            personalisedRecommendations ?? this.personalisedRecommendations,
        shareDesignsWithAssistant:
            shareDesignsWithAssistant ?? this.shareDesignsWithAssistant,
      );
}
