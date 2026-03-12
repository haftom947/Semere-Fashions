import 'package:cloud_firestore/cloud_firestore.dart';


class Branch {
  final String id;
  final String name;
  final String location;
  final String? phone;
  final String? email;

  Branch({
    required this.id,
    required this.name,
    required this.location,
    this.phone,
    this.email,
  });

  factory Branch.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Branch(
      id: doc.id,
      name: data['name'] ?? '',
      location: data['location'] ?? '',
      phone: data['phone'],
      email: data['email'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'location': location,
      'phone': phone,
      'email': email,
    };
  }
}