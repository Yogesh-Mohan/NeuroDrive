import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '858743498536-5mlji3sdt55pkbue61cu9p6l1dchre34.apps.googleusercontent.com',
  );

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential?> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final UserCredential userCredential = await _auth.signInWithCredential(credential);
    final User? user = userCredential.user;

    if (user != null) {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        await _firestore.collection('users').doc(user.uid).set({
          'name': user.displayName ?? 'Google Driver',
          'email': user.email ?? '',
          'phone': user.phoneNumber ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'vehicle': {
            'name': '',
            'number': '',
            'type': '',
            'model': '',
          },
        });
      }
    }
    return userCredential;
  }

  Future<UserCredential> signUpWithEmailAndPassword({
    required String name,
    required String email,
    required String password,
  }) async {
    final UserCredential credential = await _auth.createUserWithEmailAndPassword(
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
        'vehicle': {
          'name': '',
          'number': '',
          'type': '',
          'model': '',
        },
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

  Stream<DocumentSnapshot<Map<String, dynamic>>>? getUserProfileStream() {
    final uid = currentUser?.uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).snapshots();
  }

  Future<void> updateDriverProfile({required String name, required String phone}) async {
    final uid = currentUser?.uid;
    if (uid == null) throw Exception("User not logged in");
    
    await currentUser?.updateDisplayName(name.trim());
    await _firestore.collection('users').doc(uid).set({
      'name': name.trim(),
      'phone': phone.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateVehicleInfo({
    required String name,
    required String number,
    required String type,
    required String model,
  }) async {
    final uid = currentUser?.uid;
    if (uid == null) throw Exception("User not logged in");
    
    await _firestore.collection('users').doc(uid).set({
      'vehicle': {
        'name': name.trim(),
        'number': number.trim(),
        'type': type.trim(),
        'model': model.trim(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static String handleAuthError(FirebaseAuthException e) {
    return e.message ?? 'Authentication error occurred. Please try again.';
  }
}
