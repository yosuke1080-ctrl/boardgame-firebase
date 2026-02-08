import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static Future<User> signInAnonymously() async {
    final result = await FirebaseAuth.instance.signInAnonymously();
    return result.user!;
  }
}
