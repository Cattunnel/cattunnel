/// Server names come from links, config files and subscriptions. Drops control
/// characters and the bidi marks, overrides and isolates that can make a name
/// read as something else (U+202E shows the rest of the name backwards).
/// ZWJ and variation selectors stay - emoji sequences need them.
String sanitizeDisplayName(String name) => name.replaceAll(_unsafe, '').trim();

final _unsafe = RegExp('[\u0000-\u001F\u007F-\u009F\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]');
