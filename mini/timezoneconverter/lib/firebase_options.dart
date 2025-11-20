import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC2zbz-C0ORPbbjxY4puhK7jWYV36SPonE',
    appId: '1:430360843865:web:f8c08555f4b8fe6b178348',
    messagingSenderId: '430360843865',
    projectId: 'miniproject-77533',
    authDomain: 'miniproject-77533.firebaseapp.com',
    storageBucket: 'miniproject-77533.firebasestorage.app',
    measurementId: 'G-GZLFXF7QFD',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAR7-FcU_wfz0qxNrIS9lzoeTCi-fJSnH8',
    appId: '1:430360843865:android:a15e08dfdb657a9a178348',
    messagingSenderId: '430360843865',
    projectId: 'miniproject-77533',
    storageBucket: 'miniproject-77533.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDeRU4V0jdCVNL4NbOehfHp4dMGytg0kgk',
    appId: '1:430360843865:ios:693305759ed9542f178348',
    messagingSenderId: '430360843865',
    projectId: 'miniproject-77533',
    storageBucket: 'miniproject-77533.firebasestorage.app',
    androidClientId: '430360843865-obo15bq55s9768fjjaka5cvis3uud9e3.apps.googleusercontent.com',
    iosClientId: '430360843865-spbv6vvmtod21c97ns9dt9562bp1oe1e.apps.googleusercontent.com',
    iosBundleId: 'com.example.timezoneconverter',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDeRU4V0jdCVNL4NbOehfHp4dMGytg0kgk',
    appId: '1:430360843865:ios:693305759ed9542f178348',
    messagingSenderId: '430360843865',
    projectId: 'miniproject-77533',
    storageBucket: 'miniproject-77533.firebasestorage.app',
    androidClientId: '430360843865-obo15bq55s9768fjjaka5cvis3uud9e3.apps.googleusercontent.com',
    iosClientId: '430360843865-spbv6vvmtod21c97ns9dt9562bp1oe1e.apps.googleusercontent.com',
    iosBundleId: 'com.example.timezoneconverter',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyC2zbz-C0ORPbbjxY4puhK7jWYV36SPonE',
    appId: '1:430360843865:web:3477db712e67f602178348',
    messagingSenderId: '430360843865',
    projectId: 'miniproject-77533',
    authDomain: 'miniproject-77533.firebaseapp.com',
    storageBucket: 'miniproject-77533.firebasestorage.app',
    measurementId: 'G-TEFWV8W81P',
  );

}