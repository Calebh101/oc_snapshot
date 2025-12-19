import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:oc_snapshot/oc_snapshot.dart';
import 'package:plist_parser/plist_parser.dart';
import 'package:path/path.dart' as p;

const bool allowOverwriteOriginal = false;

void main(List<String> arguments) async {
  ArgParser parser = ArgParser()
    ..addFlag("help", abbr: "h", help: "Show this help message.", negatable: false)
    ..addOption("in", help: "The path to your config.plist.", mandatory: false)
    ..addOption("out", help: "The path to where you want to write the results. This defaults to your in path.")
    ..addOption("oc", help: "The path to your OC folder in your EFI.", mandatory: true)
    ..addOption("oc-version", help: "The OpenCore version for schema stuff. Example: 1.0.6")
    ..addFlag("clean", abbr: "c", help: "Clean snapshot. See README.md for more info.", negatable: false)
    ..addFlag("force-update-schema", abbr: "f", help: "Add missing or remove erroneous keys from existing snapshot entries.", negatable: false);

  late ArgResults args;
  late Map data;
  late Map result;

  try {
    args = parser.parse(arguments);
    args["oc"]; // Make sure we error here for arguments that are "mandatory"
  } catch (e) {
    print("$e\n\nUsage:\n${parser.usage}");
    exit(1);
  }

  if (args["help"]) {
    print("Usage:\n${parser.usage}");
    exit(0);
  }

  try {
    data = PlistParser().parseFileSync(args["in"]);
  } catch (e) {
    print("Invalid plist format: $e");
    data = {};
  }

  OpenCoreVersion openCoreVersion = args["oc-version"] == null || args["oc-version"].isEmpty ? OpenCoreVersion.latest() : OpenCoreVersion.from(args["oc-version"]);
  print("Found OpenCore version of $openCoreVersion");
  Directory directory = Directory(args["oc"]);

  if (!directory.existsSync()) {
    print("Error: Directory '${directory.path}' does not exist.");
    exit(1);
  }

  while (true) {
    File opencore = File(p.join(directory.path, "OpenCore.efi"));
    Directory oc = Directory(p.join(directory.path, "OC"));

    Directory acpi = Directory(p.join(directory.path, "ACPI"));
    Directory kexts = Directory(p.join(directory.path, "Kexts"));
    Directory drivers = Directory(p.join(directory.path, "Drivers"));
    Directory tools = Directory(p.join(directory.path, "Tools"));

    if ([acpi, kexts, drivers, tools].any((x) => !x.existsSync())) {
      if (oc.existsSync()) {
        print("Subfolder OC detected, rebasing there...");
        directory = oc;
        continue;
      } else {
        print("Either ACPI, Kexts, Drivers, or Tools doesn't exist in your OC folder.");
        break;
      }
    }

    if (!opencore.existsSync()) {
      print("OpenCore.efi doesn't exist, ignoring.");
    }

    result = OCSnapshot.snapshot(data, files: (acpi: OCSnapshot.listDirectory(acpi), kexts: OCSnapshot.listKexts(kexts), drivers: OCSnapshot.listDirectory(drivers), tools: OCSnapshot.listDirectory(tools)), opencoreVersion: openCoreVersion, opencoreHash: opencore.existsSync() ? await hash(opencore) : null, clean: args["clean"], forceUpdateSchema: args["force-update-schema"]);

    print("Returned from snapshotting");
    break;
  }

  String plist = OCSnapshot.toPlist(result);
  File out = File(args["out"] == null && allowOverwriteOriginal ? args["in"] : args["out"]!);

  print("Writing result to ${out.absolute.path}...");
  out.writeAsStringSync(plist);
  exit(0);
}

Future<String> hash(File file) async {
  final stream = file.openRead();
  final hash = await md5.bind(stream).first;
  return hash.toString();
}