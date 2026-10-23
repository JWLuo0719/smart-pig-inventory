import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

final inventoryRevisionProvider = StateProvider<int>((ref) => 0);
final inventoryClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);
final inventoryRouteObserver = RouteObserver<ModalRoute<dynamic>>();
