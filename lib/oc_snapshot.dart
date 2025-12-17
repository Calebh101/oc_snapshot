import 'dart:io';

import 'package:oc_snapshot/src/snapshot.plist.dart';
import 'package:path/path.dart' as p;

class OCSnapshot {
    static const int safePathLength = 128; // From OpenCOrePkg's OcStorageLib.h

    OCSnapshot._();

    static Map snapshot(Map data, {
        bool clean = false,
        bool forceUpdateSchema = false,
        OpenCoreVersion? opencoreVersion,
        String? opencoreHash,

        // File paths, relative to the `ACPI`, `Kexts`, `Drivers`, and `Tools` folders respectively.
        required ({List<String> acpi, List<String> kexts, List<String> drivers, List<String> tools}) files,

        void Function(String)? onLog,
    }) {
        Map? latestSnapshot;
        Map? targetSnapshot;
        Map? selectedSnapshot;
        Map? userSnapshot;

        opencoreHash ??= "";

        if (opencoreVersion != null && !opencoreVersion.latest) {
            OpenCoreVersion lowest = opencoreVersion;
            Map<String, dynamic>? lowestSnapshot;

            for (var s in SnapshotData.getPlist.where((x) => x["min_version"] is String)) {
                OpenCoreVersion minVersion = OpenCoreVersion.from(s["min_version"] as String);

                if (minVersion < lowest) {
                    onLog?.call("User-provided snapshot is lower than the minimum available; using ${lowest.toRawString()} instead.");
                    lowest = minVersion;
                    lowestSnapshot = s;
                }
            }

            if (lowestSnapshot != null && opencoreVersion < lowest) {
                // The snapshot provided is lower than what we have
                userSnapshot = lowestSnapshot;
            }
        }

        for (var snapshot in SnapshotData.getPlist) {
            List<String> releaseHashes = snapshot["release_hashes"] ?? [];
            List<String> allHashes = releaseHashes + (snapshot["debug_hashes"] ?? []);
            OpenCoreVersion minVersion = OpenCoreVersion.from(snapshot["min_version"]);

            if (latestSnapshot != null) {
                OpenCoreVersion latestVersion = OpenCoreVersion.from(latestSnapshot["min_version"]);

                if (minVersion > latestVersion) {
                    latestSnapshot = snapshot;
                    if (opencoreVersion?.latest ?? false) selectedSnapshot = snapshot;
                }
            } else {
                latestSnapshot = snapshot;
            }

            if (opencoreHash.isNotEmpty && allHashes.contains(opencoreHash)) {
                targetSnapshot = snapshot;
                if (opencoreVersion == null) selectedSnapshot = snapshot;
            }

            if (opencoreVersion != null && !opencoreVersion.latest && opencoreVersion >= minVersion) {
                OpenCoreVersion selectedVersion = OpenCoreVersion.from(selectedSnapshot?["min_version"]);
                if (minVersion > selectedVersion) selectedSnapshot = snapshot;
            }
        }

        selectedSnapshot ??= latestSnapshot;
        OpenCoreVersion selectedMinVersion = OpenCoreVersion.from(selectedSnapshot?["min_version"]);
        OpenCoreVersion selectedMaxVersion = selectedSnapshot?["max_version"] is String ? OpenCoreVersion.from(selectedSnapshot?["max_version"]) : OpenCoreVersion.latest();
        String selectedVersion = selectedMinVersion == selectedMaxVersion ? selectedMinVersion.toRawString() : "${selectedMinVersion.toRawString()} -> ${selectedMaxVersion.toRawString()}";

        if (targetSnapshot != null && targetSnapshot != selectedSnapshot) { // Version mismatch
            OpenCoreVersion targetMinVersion = OpenCoreVersion.from(targetSnapshot["min_version"]);
            OpenCoreVersion targetMaxVersion = targetSnapshot["max_version"] is String ? OpenCoreVersion.from(targetSnapshot["max_version"]) : OpenCoreVersion.latest();

            String targetVersion = targetMinVersion == targetMaxVersion ? targetMinVersion.toRawString() : "${targetMinVersion.toRawString()} -> ${targetMaxVersion.toRawString()}";
            onLog?.call("Using user-provided schema for $selectedVersion rather than the detected $targetVersion.");
        } else {
            onLog?.call("Using schema for $selectedVersion.");
        }

        if (selectedSnapshot == null) {
            onLog?.call("No snapshot selected.");
            print("No snapshot selected.");
            exit(1);
        }

        Map snapshotAcpiAdd = selectedSnapshot["acpi_add"] ?? {};
        Map snapshotKextsAdd = selectedSnapshot["kext_add"] ?? {};
        Map snapshotToolsAdd = selectedSnapshot["tool_add"] ?? {};
        Map snapshotDriversAdd = selectedSnapshot["driver_add"] ?? {};

        List<({Object item, String name, List<String> pathsTooLong})> longPaths = [];
        List<String> newAcpi = [];

        if (data["ACPI"] is! Map) data["ACPI"] = {"Add": []};
        if (data["ACPI"]["Add"] is! List) data["ACPI"]["Add"] = [];

        for (String path in files.acpi) {
            String name = p.basename(path);
            if (!name.startsWith(".") && (name.toLowerCase().endsWith(".aml") || name.toLowerCase().endsWith(".bin"))) newAcpi.add(path);
        }

        List acpiAdd = clean ? [] : data["ACPI"]["Add"];

        for (var path in newAcpi..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))) {
            if (acpiAdd.whereType<Map>().map((x) => x["path"] ?? "").contains(path)) continue;

            var newEntry = {
                "Comment": p.basename(path),
                "Enabled": true,
                "Path": path,
            };

            for (var e in snapshotAcpiAdd.entries) newEntry[e.key] = snapshotAcpiAdd[e.key];
            acpiAdd.add(newEntry);
        }

        var newAcpiAdd = [];

        for (var entry in acpiAdd.whereType<Map>()) {
            if (!newAcpi.contains((entry["Path"] ?? "").toLowerCase())) continue;
            newAcpiAdd.add(entry);
            longPaths.addAll(checkPathLength(entry, "ACPI\\"));
        }

        List<String> acpiEnabled = [];
        List<String> acpiDuplicates = [];
        List<Map> acpiDuplicatesDisabled = [];

        for (var e in newAcpiAdd) {
            if (e["Enabled"] ?? false) {
                if (acpiEnabled.contains(e["Path"] ?? "")) {
                    var newA = {};
                    for (var key in newA.keys) newA[key] = e[key];
                    newA["Enabled"] = false;
                    acpiDuplicatesDisabled.add(newA);
                    if (!acpiDuplicates.contains(e["Path"] ?? "")) acpiDuplicates.add(e["Path"]);
                } else {
                    acpiEnabled.add(e["Path"] ?? "");
                    acpiDuplicatesDisabled.add(e);
                }
            }
        }

        if (acpiDuplicates.isNotEmpty) {
            onLog?.call("Duplicate ACPI entries have been disabled: ${acpiDuplicates.join(", ")}");
            newAcpiAdd = acpiDuplicatesDisabled;
        }

        data["ACPI"]["Add"] = newAcpiAdd;

        onLog?.call("All done! Finished OC ${clean ? "clean snapshot" : "snapshot"}.");
        return data;
    }

    static List<({Object item, String name, List<String> pathsTooLong})> checkPathLength(Object item, String prefix) {
        int length = prefix.length;
        List<String> pathsTooLong = [];
        late String name;

        if (item is Map<String, dynamic>) {
            name = p.basename(item["Path"] ?? item["BundlePath"] ?? "Unknown Name");

            for (var key in item.keys) {
                if (key.toLowerCase().contains("path") && item[key] is String) {
                    if (["executablepath", "plistpath"].contains(key.toLowerCase()) && item["BundlePath"] is String) {
                        if (length + "${item["BundlePath"]}\\${item[key]}".length > safePathLength) {
                            pathsTooLong.add(key);
                        }
                    } else if (length + key.length > safePathLength) {
                        pathsTooLong.add(key);
                    }
                }
            }
        } else if (item is String) {
            name = p.basename(item);
            if (length + item.length > safePathLength) pathsTooLong.add(item);
        } else {
            return [];
        }

        if (pathsTooLong.isEmpty) {
            return [];
        } else {
            return [(
                item: item,
                name: name,
                pathsTooLong: pathsTooLong,
            )];
        }
    }

    static bool pathIsValid(String path) {
        return !path.split(".").contains("__MACOSX");
    }
}

class OpenCoreVersion {
    final bool _latest;
    bool get latest => _latest;

    final int main;
    final int sub;
    final int patch;

    OpenCoreVersion(this.main, this.sub, this.patch) : _latest = false;
    OpenCoreVersion.from(String version) : main = int.tryParse(version.split(".")[0]) ?? 0, sub = int.tryParse(version.split(".")[1]) ?? 0, patch = int.tryParse(version.split(".")[2]) ?? 0, _latest = false;
    OpenCoreVersion.latest() : _latest = true, main = 0, sub = 0, patch = 0;

    bool operator <(OpenCoreVersion other) {
        if (latest) {
            if (other.latest) {
                return true;
            } else {
                return false;
            }
        } else if (other.latest) {
            return true;
        } else if (main == other.main) {
            if (sub == other.sub) {
                if (patch == other.patch) {
                    return false;
                } else {
                    return patch < other.patch;
                }
            } else {
                return sub < other.sub;
            }
        } else {
            return main < other.main;
        }
    }

    bool operator >(OpenCoreVersion other) => other < this;

    bool operator <=(OpenCoreVersion other) => !(this > other);

    bool operator >=(OpenCoreVersion other) => !(this < other);

    bool operator ==(Object other) {
        if (other is! OpenCoreVersion) return false;

        return latest == other.latest &&
            main == other.main &&
            sub == other.sub &&
            patch == other.patch;
    }

    @override
    String toString() {
        return _latest ? "Latest" : "V. ${toRawString()}";
    }

    String toRawString() {
        return _latest ? "Latest" : [main, sub, patch].join(".");
    }
}