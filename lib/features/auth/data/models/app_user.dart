import '../../../../models/store_profile.dart';
import 'user_preferences.dart';

enum UserRole {
  homeowner,
  supplier;

  static UserRole fromString(String role) {
    switch (role.toLowerCase()) {
      case 'supplier':
        return UserRole.supplier;
      case 'homeowner':
      default:
        return UserRole.homeowner;
    }
  }

  String get firestoreValue => name;
}

class AppUser {
  final String uid;
  final String email;
  final String name;
  final UserRole role;
  final String? phone;
  final String? address;
  final String? profilePicture;

  final String verificationStatus;

  final String? businessName;
  final String? businessPhone;
  final String? businessAddress;
  final StoreProfile storeProfile;

  final bool twoFactorEnabled;
  final bool isGuest;
  final bool twoFactorPending;
  final bool onboardingCompleted;
  final DesignPreferences designPreferences;
  final NotificationSettings notificationSettings;
  final PrivacySettings privacySettings;

  final DateTime createdAt;
  final DateTime updatedAt;

  const AppUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    this.phone,
    this.address,
    this.profilePicture,
    this.verificationStatus = 'none',
    this.businessName,
    this.businessPhone,
    this.businessAddress,
    this.storeProfile = const StoreProfile(),
    this.twoFactorEnabled = false,
    this.twoFactorPending = false,
    this.onboardingCompleted = true,
    this.designPreferences = const DesignPreferences(),
    this.notificationSettings = const NotificationSettings(),
    this.privacySettings = const PrivacySettings(),
    required this.createdAt,
    required this.updatedAt,
    this.isGuest = false,
  });

  // Browsing without an account (Firebase anonymous sign-in): a homeowner
  // who can explore everything but must sign up to buy or save.
  factory AppUser.guest(String uid) {
    final now = DateTime.now();
    return AppUser(
      uid: uid,
      email: '',
      name: 'Guest',
      role: UserRole.homeowner,
      onboardingCompleted: true,
      createdAt: now,
      updatedAt: now,
      isGuest: true,
    );
  }

  bool get isHomeowner => role == UserRole.homeowner;
  bool get isSupplier => role == UserRole.supplier;
  bool get isVerified => verificationStatus == 'verified';

  bool get canSubmitVerification =>
      verificationStatus == 'none' || verificationStatus == 'rejected';

  factory AppUser.fromFirestore({
    required String uid,
    required String email,
    required Map<String, dynamic> data,
  }) {
    final role = UserRole.fromString(data['role'] as String? ?? 'homeowner');
    final name = data['name'] as String? ?? '';
    return AppUser(
      uid: uid,
      email: email,
      name: name,
      role: role,
      phone: data['phone'] as String?,
      address: data['address'] as String?,
      profilePicture: data['profilePicture'] as String?,
      verificationStatus: data['verificationStatus']?.toString() ?? 'none',
      businessName: data['businessName']?.toString() ??
          (role == UserRole.supplier ? name : null),
      businessPhone: data['businessPhone']?.toString(),
      businessAddress: data['businessAddress']?.toString(),
      storeProfile: StoreProfile.fromMap(data['storeProfile']),
      // Sellers default to two-step sign-in until they switch it off.
      twoFactorEnabled: data.containsKey('twoFactorEnabled')
          ? data['twoFactorEnabled'] == true
          : role == UserRole.supplier,
      onboardingCompleted: data['onboardingCompleted'] == true,
      designPreferences: DesignPreferences.fromMap(data['designPreferences']),
      notificationSettings:
          NotificationSettings.fromMap(data['notificationSettings']),
      privacySettings: PrivacySettings.fromMap(data['privacySettings']),
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'role': role.firestoreValue,
      'phone': phone ?? '',
      'address': address ?? '',
      'profilePicture': profilePicture ?? '',
      'verificationStatus': verificationStatus,
      'businessName': businessName ?? '',
      'businessPhone': businessPhone ?? '',
      'businessAddress': businessAddress ?? '',
      'updatedAt': DateTime.now(),
    };
  }

  AppUser copyWith({
    String? name,
    String? phone,
    String? address,
    String? profilePicture,
    String? verificationStatus,
    String? businessName,
    String? businessPhone,
    String? businessAddress,
    StoreProfile? storeProfile,
    String? email,
    bool? twoFactorEnabled,
    bool? twoFactorPending,
    bool? onboardingCompleted,
    DesignPreferences? designPreferences,
    NotificationSettings? notificationSettings,
    PrivacySettings? privacySettings,
  }) {
    return AppUser(
      uid: uid,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      profilePicture: profilePicture ?? this.profilePicture,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      businessName: businessName ?? this.businessName,
      businessPhone: businessPhone ?? this.businessPhone,
      businessAddress: businessAddress ?? this.businessAddress,
      storeProfile: storeProfile ?? this.storeProfile,
      twoFactorEnabled: twoFactorEnabled ?? this.twoFactorEnabled,
      twoFactorPending: twoFactorPending ?? this.twoFactorPending,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      designPreferences: designPreferences ?? this.designPreferences,
      notificationSettings: notificationSettings ?? this.notificationSettings,
      privacySettings: privacySettings ?? this.privacySettings,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      isGuest: isGuest,
    );
  }

  @override
  String toString() =>
      'AppUser(uid: $uid, email: $email, name: $name, role: $role)';
}

DateTime _toDate(dynamic value) {
  if (value is DateTime) return value;
  try {
    final toDate = value?.toDate;
    if (toDate is Function) {
      final parsed = value.toDate();
      if (parsed is DateTime) return parsed;
    }
  } catch (_) {}
  return DateTime.now();
}
