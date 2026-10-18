import '../network/api_client.dart';
import 'driver_backend_gateway.dart';

class LocalBackendDriverGateway implements DriverBackendGateway {
  LocalBackendDriverGateway({required this.apiClient});

  final ApiClient apiClient;

  @override
  Future<DriverProfileSummary> ensureAndGetProfile() async {
    // 1. Ensure profile exists on backend
    await apiClient.post('/api/riders/ensure');

    // 2. Fetch profile
    final response = await apiClient.get('/api/riders/me');
    final data = response['data'] as Map<String, dynamic>;
    final driver = data['driver'] as Map<String, dynamic>;

    return DriverProfileSummary(
      accountStatus: driver['accountStatus'] as String? ?? 'active',
      registrationStatus: driver['registrationStatus'] as String? ?? 'approved',
      identityVerificationStatus:
          driver['identityVerificationStatus'] as String? ?? 'verified',
      deviceEnrollmentStatus:
          driver['deviceEnrollmentStatus'] as String? ?? 'enrolled',
      requiredDocumentsStatus: 'verified',
      trainingStatus: 'complete',
      riskStatus: driver['riskStatus'] as String? ?? 'ACTIVE',
    );
  }

  @override
  Future<String> requestDeviceEnrollment(String platform) async {
    final response = await apiClient.post(
      '/api/riders/devices',
      body: {'platform': platform},
    );
    final data = response['data'] as Map<String, dynamic>;
    return data['deviceEnrollmentId'] as String;
  }
}
