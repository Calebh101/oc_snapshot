import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:plist_parser/plist_parser.dart';

const int prettyIndent = 2;

void main(List<String> arguments) {
  final ArgParser parser = ArgParser()
    ..addOption("path", help: "The path of the plist to convert to JSON.", mandatory: true)
    ..addFlag("pretty", abbr: "p", help: "Print the JSON pretty.", negatable: false);

  late ArgResults args;
  late Map data;

  try {
    args = parser.parse(arguments);
  } catch (e) {
    print("$e\n\nUsage:\n${parser.usage}");
    exit(1);
  }

  try {
    data = PlistParser().parseFileSync(args["path"]);
  } catch (e) {
    print("Invalid plist format:\n$e");
    exit(1);
  }

  final normalized = normalize(data);
  late String result;

  if (args["pretty"]) {
    result = JsonEncoder.withIndent(' ' * prettyIndent).convert(normalized);
  } else {
    result = jsonEncode(normalized);
  }

  print(result);
  exit(0);
}

dynamic normalize(dynamic value) {
  if (value is Map) {
    final keys = value.keys.toList();

    if (keys.isNotEmpty && keys.every((k) => k is int) && consecutive(keys)) {
      return List.generate(
        keys.length,
        (i) => normalize(value[i]),
      );
    }

    return {
      for (final entry in value.entries)
        entry.key.toString(): normalize(entry.value),
    };
  }

  if (value is Iterable) return value.map(normalize).toList();
  return value;
}

bool consecutive(List keys) {
  keys.sort();
  for (var i = 0; i < keys.length; i++) if (keys[i] != i) return false;
  return true;
}