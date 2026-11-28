import 'package:flutter/widgets.dart';

/// Tracks the root navigator's routes so we can avoid pushing a screen that
/// is already somewhere in the stack (class -> teacher -> same class ...).
class RouteStackObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _routes.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (newRoute == null) return;
    if (i >= 0) {
      _routes[i] = newRoute;
    } else {
      _routes.add(newRoute);
    }
  }

  /// True if a live route named [name] is in the stack.
  bool contains(String name) {
    _routes.removeWhere((r) => !r.isActive); // drop routes from disposed navigators
    return _routes.any((r) => r.settings.name == name);
  }
}

final routeStack = RouteStackObserver();

/// Route names for screens that should appear at most once in the stack.
String teacherRouteName(String teacherKey) => 'teacher:$teacherKey';
String sessionRouteName(String sessionId) => 'session:$sessionId';

/// If a route named [name] is already in the stack, pops back to it and
/// returns true. Otherwise returns false and the caller should push.
bool popToExisting(BuildContext context, String name) {
  if (!routeStack.contains(name)) return false;
  Navigator.of(context, rootNavigator: true).popUntil((r) => r.settings.name == name);
  return true;
}
