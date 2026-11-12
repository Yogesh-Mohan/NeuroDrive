import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_drive/core/models/user_profile_model.dart';

void main() {
  group('Phase 1 - VehicleModel & UserProfile Model Tests', () {
    test('VehicleModel initializes with default values', () {
      const vehicle = VehicleModel();
      expect(vehicle.name, '');
      expect(vehicle.registrationNumber, '');
      expect(vehicle.type, '');
      expect(vehicle.model, '');
      expect(vehicle.isEmpty, isTrue);
      expect(vehicle.isNotEmpty, isFalse);
    });

    test('VehicleModel fromMap parses both registrationNumber and number', () {
      final mapWithReg = {
        'name': 'Tesla Model 3',
        'registrationNumber': 'CA-9876',
        'type': 'Sedan',
        'model': '2024 Long Range',
      };
      final v1 = VehicleModel.fromMap(mapWithReg);
      expect(v1.name, 'Tesla Model 3');
      expect(v1.registrationNumber, 'CA-9876');
      expect(v1.type, 'Sedan');
      expect(v1.model, '2024 Long Range');
      expect(v1.isNotEmpty, isTrue);

      final mapWithNumber = {
        'name': 'Honda Civic',
        'number': 'NY-1234',
        'type': 'Hatchback',
        'model': '2023 EX',
      };
      final v2 = VehicleModel.fromMap(mapWithNumber);
      expect(v2.registrationNumber, 'NY-1234');
    });

    test('VehicleModel toMap exports all required fields', () {
      const vehicle = VehicleModel(
        name: 'Ford Mustang',
        registrationNumber: 'TX-5544',
        type: 'Coupe',
        model: 'GT 5.0',
      );

      final map = vehicle.toMap();
      expect(map['name'], 'Ford Mustang');
      expect(map['registrationNumber'], 'TX-5544');
      expect(map['number'], 'TX-5544');
      expect(map['type'], 'Coupe');
      expect(map['model'], 'GT 5.0');
    });

    test('VehicleModel copyWith updates fields properly', () {
      const original = VehicleModel(
        name: 'Audi A4',
        registrationNumber: 'DL-01-AB-1234',
        type: 'Sedan',
        model: '2022',
      );

      final updated = original.copyWith(
        name: 'Audi A6',
        model: '2024',
      );

      expect(updated.name, 'Audi A6');
      expect(updated.registrationNumber, 'DL-01-AB-1234');
      expect(updated.model, '2024');
      expect(updated.type, 'Sedan');
    });

    test('UserProfile copyWith preserves existing values', () {
      final created = DateTime.now().subtract(const Duration(days: 10));
      final updated = DateTime.now();

      final profile = UserProfile(
        uid: 'user_123',
        name: 'Jane Doe',
        email: 'jane@example.com',
        phone: '+1234567890',
        createdAt: created,
        updatedAt: updated,
        vehicle: const VehicleModel(name: 'BMW 330i'),
      );

      final modified = profile.copyWith(
        name: 'Jane Smith',
        phone: '+1987654321',
      );

      expect(modified.uid, 'user_123');
      expect(modified.name, 'Jane Smith');
      expect(modified.email, 'jane@example.com');
      expect(modified.phone, '+1987654321');
      expect(modified.createdAt, created);
      expect(modified.vehicle.name, 'BMW 330i');
    });
  });

  group('Phase 1 - Validation Logic Tests', () {
    test('Email regex validation validates valid and invalid emails', () {
      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

      expect(emailRegex.hasMatch('driver@neurodrive.ai'), isTrue);
      expect(emailRegex.hasMatch('test.user@company.co'), isTrue);
      expect(emailRegex.hasMatch('plainaddress'), isFalse);
      expect(emailRegex.hasMatch('user@'), isFalse);
      expect(emailRegex.hasMatch('@domain.com'), isFalse);
    });

    test('Vehicle required fields validation', () {
      bool validateVehicle({
        required String name,
        required String number,
        required String type,
        required String model,
      }) {
        return name.trim().isNotEmpty &&
            number.trim().isNotEmpty &&
            type.trim().isNotEmpty &&
            model.trim().isNotEmpty;
      }

      expect(
        validateVehicle(name: 'Car', number: '123', type: 'SUV', model: '2024'),
        isTrue,
      );
      expect(
        validateVehicle(name: '', number: '123', type: 'SUV', model: '2024'),
        isFalse,
      );
      expect(
        validateVehicle(name: 'Car', number: '  ', type: 'SUV', model: '2024'),
        isFalse,
      );
      expect(
        validateVehicle(name: 'Car', number: '123', type: '', model: '2024'),
        isFalse,
      );
      expect(
        validateVehicle(name: 'Car', number: '123', type: 'SUV', model: ''),
        isFalse,
      );
    });
  });
}
