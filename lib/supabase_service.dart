import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseClient get _client => Supabase.instance.client;
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  // ...existing code...

  /// Call the RPC that marks a ticket printed once.
  Future<void> markTicketPrinted(String ticketId) async {
    final res = await _client.rpc('mark_ticket_printed', params: {'p_ticket_id': ticketId}).execute();
    if (res.error != null) {
      throw res.error!;
    }
  }

  // ...existing code...
}