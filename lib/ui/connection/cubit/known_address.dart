import 'package:equatable/equatable.dart';

/// The address shown in the IP address dialog when nothing is known yet.
const exampleAddress = '192.168.1.20';

/// An address the user can pick in the IP address dialog, with what is known
/// about it ("saved and connected", a computer name, "unknown").
class KnownAddress extends Equatable {
  /// Creates the entry.
  const KnownAddress({required this.address, required this.description});

  /// The IPv4 address.
  final String address;

  /// What is known about it, never empty.
  final String description;

  @override
  List<Object?> get props => [address, description];
}
