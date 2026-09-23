import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme.dart';
import '../../../models/address.dart';

/// Bottom-sheet form for adding a delivery address. The "use my current
/// location" button is opt-in and only runs when the user taps it — unlike
/// the old website, which fired a geolocation prompt automatically on page
/// load. Nothing here reads location without an explicit tap.
Future<Address?> showAddAddressSheet(BuildContext context) {
  return showModalBottomSheet<Address>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AddressFormSheet(),
  );
}

class _AddressFormSheet extends StatefulWidget {
  const _AddressFormSheet();

  @override
  State<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<_AddressFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController(text: 'Home');
  final _line1 = TextEditingController();
  final _line2 = TextEditingController();
  final _landmark = TextEditingController();
  final _city = TextEditingController(text: 'Hajipur');
  final _state = TextEditingController(text: 'Bihar');
  final _pincode = TextEditingController();
  double? _lat;
  double? _lng;
  bool _locating = false;

  @override
  void dispose() {
    for (final c in [_label, _line1, _line2, _landmark, _city, _state, _pincode]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final permission = await Geolocator.checkPermission();
      var granted = permission;
      if (granted == LocationPermission.denied) {
        granted = await Geolocator.requestPermission();
      }
      if (granted == LocationPermission.denied || granted == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied. You can still enter your address manually.')),
        );
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Please turn on location services and try again.')));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _lat = pos.latitude;
      _lng = pos.longitude;
      try {
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          setState(() {
            _line1.text = [p.street, p.subLocality].where((e) => (e ?? '').isNotEmpty).join(', ');
            _city.text = (p.locality?.isNotEmpty ?? false) ? p.locality! : _city.text;
            _state.text = (p.administrativeArea?.isNotEmpty ?? false) ? p.administrativeArea! : _state.text;
            _pincode.text = p.postalCode ?? _pincode.text;
          });
        }
      } catch (_) {
        // Reverse geocoding failed — we still have lat/lng, user can fill the rest manually.
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location captured — please check the details below.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not get your location right now.')));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final address = Address(
      id: '',
      label: _label.text.trim().isEmpty ? 'Home' : _label.text.trim(),
      line1: _line1.text.trim(),
      line2: _line2.text.trim().isEmpty ? null : _line2.text.trim(),
      landmark: _landmark.text.trim().isEmpty ? null : _landmark.text.trim(),
      city: _city.text.trim(),
      state: _state.text.trim(),
      pincode: _pincode.text.trim().isEmpty ? null : _pincode.text.trim(),
      lat: _lat,
      lng: _lng,
    );
    Navigator.of(context).pop(address);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Form(
              key: _formKey,
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Add delivery address', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _locating ? null : _useCurrentLocation,
                    icon: _locating
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location, size: 18),
                    label: Text(_locating ? 'Locating…' : 'Use my current location'),
                  ),
                  const SizedBox(height: 16),
                  _field(_label, 'Label (Home, Shop, etc.)'),
                  _field(_line1, 'House / Flat / Street', required: true),
                  _field(_line2, 'Area / Locality (optional)'),
                  _field(_landmark, 'Landmark (optional)'),
                  Row(
                    children: [
                      Expanded(child: _field(_city, 'City', required: true)),
                      const SizedBox(width: 12),
                      Expanded(child: _field(_state, 'State', required: true)),
                    ],
                  ),
                  _field(_pincode, 'Pincode', keyboardType: TextInputType.number),
                  const SizedBox(height: 10),
                  ElevatedButton(onPressed: _save, child: const Text('Save address')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {bool required = false, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
      ),
    );
  }
}
