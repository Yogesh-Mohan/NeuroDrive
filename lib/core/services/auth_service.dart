import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_profile_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '858743498536-5mlji3sdt55pkbue61cu9p6l1dchre34.apps.googleusercontent.com',
  );

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential?> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;
    if (googleAuth.idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-google-id-token',
        message:
            'Google did not return an ID token. Check the Firebase OAuth client configuration.',
      );
    }

    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final UserCredential userCredential = await _auth.signInWithCredential(
      credential,
    );
    final User? user = userCredential.user;

    if (user != null) {
      final userRef = _firestore.collection('users').doc(user.uid);
      final userDoc = await userRef.get().timeout(const Duration(seconds: 10));
      await userRef
          .set({
            'name': user.displayName ?? 'Google Driver',
            'email': user.email ?? '',
            'phone': user.phoneNumber ?? '',
            'updatedAt': FieldValue.serverTimestamp(),
            if (!userDoc.exists) 'createdAt': FieldValue.serverTimestamp(),
            if (!userDoc.exists)
              'vehicle': {'name': '', 'number': '', 'type': '', 'model': ''},
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    }
    return userCredential;
  }

  Future<UserCredential> signUpWithEmailAndPassword({
    required String name,
    required String email,
    required String password,
  }) async {
    final UserCredential credential = await _auth
        .createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );

    final User? user = credential.user;
    if (user != null) {
      await user.updateDisplayName(name.trim());
      await _firestore.collection('users').doc(user.uid).set({
        'name': name.trim(),
        'email': email.trim(),
        'phone': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'vehicle': {'name': '', 'number': '', 'type': '', 'model': ''},
      });
    }
    return credential;
  }

  Future<UserCredential> loginWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Stream current user's profile document snapshot
  Stream<DocumentSnapshot<Map<String, dynamic>>>? getUserProfileStream() {
    final uid = currentUser?.uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).snapshots();
  }

  /// Get current user's profile as a model snapshot once
  Future<UserProfile?> getUserProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromFirestore(
      doc,
      fallbackEmail: user.email,
      fallbackName: user.displayName,
    );
  }

  /// Save or update Driver Profile.
  /// Preserves `createdAt` if the document already exists, sets it if new.
  /// Always updates `updatedAt` with server timestamp.
  Future<void> updateDriverProfile({
    required String name,
    required String phone,
    String? email,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception("User not authenticated.");

    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    final cleanEmail = (email != null && email.trim().isNotEmpty)
        ? email.trim()
        : (user.email ?? '');

    if (cleanName.isEmpty) {
      throw Exception("Driver name cannot be empty.");
    }

    final docRef = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await docRef.get();

    final Map<String, dynamic> data = {
      'name': cleanName,
      'email': cleanEmail,
      'phone': cleanPhone,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (!docSnapshot.exists || docSnapshot.data()?['createdAt'] == null) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }

    await docRef.set(data, SetOptions(merge: true));

    // Also update FirebaseAuth displayName if changed
    if (user.displayName != cleanName) {
      try {
        await user.updateDisplayName(cleanName);
      } catch (_) {
        // Non-critical, Firestore is the source of truth
      }
    }
  }

  /// Save or update Vehicle Information inside `users/{uid}` -> `vehicle` map.
  /// Preserves `createdAt` on the parent doc if it already exists, and sets `updatedAt`.
  Future<void> updateVehicleInfo({
    required String name,
    required String number,
    required String type,
    required String model,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception("User not authenticated.");

    final cleanName = name.trim();
    final cleanNumber = number.trim();
    final cleanType = type.trim();
    final cleanModel = model.trim();

    if (cleanName.isEmpty) {
      throw Exception("Vehicle name cannot be empty.");
    }
    if (cleanNumber.isEmpty) {
      throw Exception("Registration number cannot be empty.");
    }
    if (cleanType.isEmpty) {
      throw Exception("Vehicle type cannot be empty.");
    }
    if (cleanModel.isEmpty) {
      throw Exception("Vehicle model cannot be empty.");
    }

    final docRef = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await docRef.get();

    final Map<String, dynamic> data = {
      'vehicle': {
        'name': cleanName,
        'registrationNumber': cleanNumber,
        'number': cleanNumber, // backwards compatibility
        'type': cleanType,
        'model': cleanModel,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (!docSnapshot.exists || docSnapshot.data()?['createdAt'] == null) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }

    await docRef.set(data, SetOptions(merge: true));
  }

  static String handleAuthError(FirebaseAuthException e) {
    return e.message ?? 'Authentication error occurred. Please try again.';
  }
}
