import '../network/api_client.dart';
import '../../features/driver/driver_journey_screens.dart';

abstract interface class DeliveryRepository {
  Future<List<DriverOrderSummary>> getDeliveries();
  Future<void> acceptDelivery(String deliveryId);
  Future<void> completeDelivery(String deliveryId);
}

class LocalBackendDeliveryRepository implements DeliveryRepository {
  LocalBackendDeliveryRepository({required this.apiClient});

  final ApiClient apiClient;

  @override
  Future<List<DriverOrderSummary>> getDeliveries() async {
    final response = await apiClient.get('/api/deliveries');
    final data = response['data'] as Map<String, dynamic>;
    final deliveries = data['deliveries'] as List<dynamic>? ?? const [];

    return deliveries.map((d) {
      final item = Map<String, dynamic>.from(d as Map);
      return DriverOrderSummary(
        id: item['id'] as String,
        title: item['title'] as String,
        pickup: item['pickup'] as String,
        dropoff: item['dropoff'] as String,
        amount: item['amount'] as int,
        distance: item['distance'] as String,
        eta: item['eta'] as String,
        serviceType: item['serviceType'] as String,
        recipientLabel: item['recipientLabel'] as String,
        notes: item['notes'] as String? ?? '',
        tags: item['tags'] as String? ?? '',
      );
    }).toList(growable: false);
  }

  @override
  Future<void> acceptDelivery(String deliveryId) async {
    await apiClient.post('/api/deliveries/$deliveryId/accept');
  }

  @override
  Future<void> completeDelivery(String deliveryId) async {
    await apiClient.post('/api/deliveries/$deliveryId/complete');
  }
}
