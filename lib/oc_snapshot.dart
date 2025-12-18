import 'dart:io';

import 'package:oc_snapshot/src/snapshot.plist.dart';
import 'package:path/path.dart' as p;
import 'package:plist_parser/plist_parser.dart';

class OCSnapshot {
    /// From OpenCorePkg's OcStorageLib.h.
    static const int safePathLength = 128;

    OCSnapshot._();

    /// OC snapshot the inputted JSON data.
    ///
    /// [clean] will force a clean snapshot, where `ACPI`, `Kexts`, `Drivers`, and `Tools` are all cleared in the config.plist before re-adding to the config.plist.
    ///
    /// [forceUpdateSchema] will delete extra keys and add missing keys.
    ///
    /// [opencoreVersion] is the OpenCore version you're using, and [opencoreHash] is the MD5 hash of OpenCore.efi.
    ///
    /// [files] is a list of the paths of `ACPI`, `Kexts`, `Drivers`, and `Tools` in `EFI/OC`.
    ///
    /// [onLog] is called when the package wants to log something. It can be ignored, but you can also make it use either [print] or a custom logging solution.
    static Map snapshot(Map data, {
        bool clean = false,
        bool forceUpdateSchema = false,
        OpenCoreVersion? opencoreVersion,
        String? opencoreHash,

        // File paths, relative to the `ACPI`, `Kexts`, `Drivers`, and `Tools` folders respectively.
        required ({List<String> acpi, List<KextData> kexts, List<String> drivers, List<String> tools}) files,

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

            for (var s in Snapshot.plist.where((x) => x["min_version"] is String)) {
                OpenCoreVersion minVersion = OpenCoreVersion.from(s["min_version"] as String);

                if (minVersion < opencoreVersion) {
                    lowest = minVersion;
                    lowestSnapshot = s;
                }
            }

            if (lowestSnapshot != null && opencoreVersion < lowest) {
                // The snapshot provided is lower than what we have
                onLog?.call("User-provided snapshot is lower than the minimum available; using ${lowest.toRawString()} instead.");
                userSnapshot = lowestSnapshot;
            }
        }

        for (var snapshot in Snapshot.plist) {
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

        onLog?.call("Snapshotting ${newAcpi.length} ACPI files");
        List acpiAdd = clean ? [] : data["ACPI"]["Add"];

        for (var path in newAcpi..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))) {
            if (acpiAdd.whereType<Map>().map((x) => x["Path"] ?? "").contains(path)) continue;

            var newEntry = {
                "Comment": p.basename(path),
                "Enabled": true,
                "Path": path,
            };

            for (var e in snapshotAcpiAdd.entries) newEntry[e.key] = snapshotAcpiAdd[e.key];
            acpiAdd.add(newEntry);
        }

        var newAcpiAdd = [];
        var newAcpiLower = newAcpi.map((x) => x.toLowerCase()).toSet();

        for (var entry in acpiAdd.whereType<Map>()) {
            final path = (entry["Path"] ?? "").toString().toLowerCase();
            if (!newAcpiLower.contains(path)) continue;

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
                    for (var key in e.keys) newA[key] = e[key];
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
        onLog?.call("Finished ACPI snapshot: ${["acpiEnabled=${acpiEnabled.length}", "acpiDuplicates=${acpiDuplicates.length}", "acpiDuplicatesDisabled=${acpiDuplicatesDisabled.length}"].join(", ")}");

        if (data["Kexts"] is! Map) data["Kexts"] = {"Add": []};
        if (data["Kexts"]["Add"] is! List) data["Kexts"]["Add"] = [];

        List<(Map<String, dynamic> infoPlist, Map<String, dynamic> kinfo)> kextList = [];
        List<String> omittedKexts = [];

        for (var kext in files.kexts) {
            if (!pathIsValid(kext.path)) continue;
            late Map<String, dynamic> info;

            Map<String, dynamic> data = {
                "BundlePath": kext.path,
                "Comment": kext.name,
                "Enabled": true,
                "ExecutablePath": "",
                "PlistPath": kext.infoPlistPath,
            };

            try {
                Map infoPlist = kext.infoPlistData;

                if (infoPlist["CFBundleIdentifier"] is! String) {
                    onLog?.call("Omitting kext ${kext.name} for invalid CFBundleIdentifier");
                    omittedKexts.add(kext.name);
                }

                info = {
                    "CFBundleIdentifier": infoPlist["CFBundleIdentifier"],
                    "OSBundleLibraries": infoPlist["OSBundleLibraries"] ?? [],
                    "cfbi": infoPlist["CFBundleIdentifier"].toLowerCase(),
                    "osbl": (infoPlist["OSBundleLibraries"] as Map? ?? {}).keys.whereType<String>().map((x) => x.toLowerCase()).toList(),
                    "ExecutablePath": kext.executablePath,
                };
            } catch (e) {
                onLog?.call("Omitting kext ${kext.name} for unknown error: $e");
                omittedKexts.add(kext.name);
                continue;
            }

            kextList.add((data, info));
        }

        if (omittedKexts.isNotEmpty) {
            onLog?.call("Invalid kexts omitted: ${omittedKexts.join(", ")}");
        }

        List<String> bundles = kextList.map((x) => x.$1["BundlePath"] ?? "").whereType<String>().toList();
        List kexts = clean ? [] : data["Kernel"]["Add"];
        List originalKexts = kexts.whereType<Map>().where((x) => bundles.contains(x["BundlePath"] ?? "")).toList();

        for (var r in kextList) {
            var kext = r.$1;
            var info = r.$2;

            if (kexts.whereType<Map>().map((x) => x["BundlePath"] ?? "").contains(kext["BundlePath"])) continue; // We already have it
            kexts.add(kext);
        }

        List<Map> newKexts = [];

        for (var kext in kexts) {
            if (kext is! Map || kext["BundlePath"] is! String) continue;

            (Map<String, dynamic>, Map<String, dynamic>)? match = kextList.cast<(Map<String, dynamic>, Map<String, dynamic>)?>().where((x) => x!.$1["BundlePath"] is String).firstWhere(
                (x) => x!.$1["BundlePath"].toLowerCase() == kext["BundlePath"].toLowerCase(),
                orElse: () => null,
            );

            if (match == null) continue;

            for (var check in ["ExecutablePath", "PlistPath"]) {
                if (kext[check] != match.$1["check"]) {
                    kext[check] = match.$1["check"] ?? "";
                }
            }

            newKexts.add(kext);
        }

        List<(Map kext, List<(Map<dynamic, dynamic>, Map<String, dynamic>)> parents)> unorderedKexts = [];

        for (var kext in newKexts) {
            Map<String, dynamic>? info;
            List<(Map<dynamic, dynamic>, Map<String, dynamic>)> parents = [];
            List<Map<dynamic, dynamic>> children = [];

            for (var x in kextList) {
                if ((x.$1["BundlePath"] ?? "") == (kext["BundlePath"] ?? "")) {
                    info = x.$2;
                    break;
                }
            }

            if (info == null) continue;

            for (var z in newKexts) {
                for (var y in kextList) {
                    if (z["BundlePath"] == y.$1["BundlePath"]) {
                        if ((y.$2["osbl"] as List? ?? []).contains(y.$2["cfbi"] ?? "")) {
                            parents.add((z, y.$2));
                        }
                    }
                }
            }

            for (var y in kextList.where((y) => y.$2["osbl"].contains(info!["cfbi"]))) {
                for (var z in newKexts) {
                    if ((z['BundlePath'] ?? '') == (y.$1['BundlePath'] ?? '')) {
                        children.add(z);
                    }
                }
            }

            unorderedKexts.add((kext, parents));
        }

        List<Map<dynamic, dynamic>> orderedKexts = [];
        List<(Map<dynamic, dynamic>, Map<String, dynamic>)> disabledParents = [];
        List<Map<dynamic, dynamic>> cyclicKexts = [];

        int loopsWithoutChanges = 0;
        bool cyclicDependencies = false;

        while (unorderedKexts.isNotEmpty) {
            var kext = unorderedKexts.removeAt(0);

            if (kext.$2.isNotEmpty) {
                List<String> enabledParents = kext.$2.where((x) => x.$1["Enabled"] == true && x.$2["cfbi"] is String).map((x) => x.$2["cfbi"]).whereType<String>().toList();

                if (kext.$1["Enabled"] == true) {
                    for (var p in kext.$2) {
                        String? cf = p.$2["cfbi"];
                        if (cf == null) continue;
                        if (enabledParents.contains(cf)) continue; // We already have an enabled copy
                        if (disabledParents.any((x) => x.$2["cfbi"] == cf)) continue;
                        disabledParents.add(p);
                    }
                }

                if (!(kext.$2.map((x) => orderedKexts.contains(x.$1))).every((x) => x)) {
                    loopsWithoutChanges++;
                    cyclicKexts.add(kext.$1);

                    if (loopsWithoutChanges > unorderedKexts.length) {
                        cyclicDependencies = true;
                        break;
                    }

                    unorderedKexts.add(kext);
                    continue;
                }
            }

            cyclicKexts.clear();
            loopsWithoutChanges = 0;
            orderedKexts.add(kext.$1);
        }

        if (cyclicDependencies) {
            onLog?.call("Kexts with cyclic dependencies have been omitted: ${cyclicKexts.map((x) => x["BundlePath"] is String ? x["BundlePath"] : "Unknown kext").join(", ")}");
        }

        var missingKexts = orderedKexts.where((x) => !originalKexts.contains(x));
        originalKexts.addAll(missingKexts);
        List<String> rearranged = [];

        while (true) {
            List<String> check1 = orderedKexts.where((x) => !rearranged.contains(x["BundlePath"])).map((x) => x["BundlePath"]).whereType<String>().toList();
            List<String> check2 = originalKexts.where((x) => !rearranged.contains(x["BundlePath"])).map((x) => x["BundlePath"]).whereType<String>().toList();

            int? outOfPlace = List.generate(check1.length, (i) => i).cast<int?>().firstWhere(
                (i) => check1[i!] != check2[i],
                orElse: () => null,
            );

            if (outOfPlace == null) break;
            rearranged.add(check2[outOfPlace]);
        }

        if (rearranged.isNotEmpty) {
            onLog?.call("Incorrect kext load order has been corrected: ${rearranged.join(", ")}");
        }

        if (disabledParents.isNotEmpty) {
            for (var p in disabledParents) p.$1["Enabled"] = true;
            onLog?.call("Disabled parent kexts have been enabled: ${disabledParents.map((x) => x.$1["BundlePath"]).join(", ")}");
        }

        List<(Map<dynamic, dynamic>, Map<String, dynamic>)> enabledKexts = [];
        List bundlesEnabled = [];
        List duplicateBundles = [];
        List duplicatesDisabled = [];
        Map<String, dynamic>? info;

        for (var kext in orderedKexts) {
            longPaths.addAll(checkPathLength(kext, "\\Kexts"));
            var tempKext = {};

            for (var x in kext.entries) tempKext[x.key] = kext[x.key];
            duplicatesDisabled.add(tempKext);
            if (tempKext["Enabled"] != true) continue;

            if ((bundlesEnabled + duplicateBundles).contains(tempKext["BundlePath"])) {
                tempKext["Enabled"] = false;
                if (!duplicateBundles.contains(tempKext["BundlePath"])) duplicateBundles.add(tempKext["BundlePath"]);
            } else {
                info = kextList.cast<(Map<String, dynamic>, Map<String, dynamic>)?>().firstWhere((x) => x!.$1["BundlePath"] == tempKext["BundlePath"], orElse: () => null)?.$2;
                if (info == null || info["cfbi"] == null) continue;

                (KernelLimitation min, KernelLimitation max) range = getMinMaxFromKext(tempKext, useMatch: snapshotKextsAdd.containsKey("MatchKernel"));
                var compKexts = enabledKexts.where((x) => x.$1["cfbi"] == info!["cfbi"]);

                for (var compInfo in compKexts) {
                    var compKext = compInfo.$1;
                    (KernelLimitation min, KernelLimitation max) compRange = getMinMaxFromKext(compKext, useMatch: snapshotKextsAdd.containsKey("MatchKernel"));
                    if (range.$1 > compRange.$2 || range.$2 < compRange.$1) continue;
                    tempKext["Enabled"] = false;
                    if (!duplicateBundles.contains(tempKext["BundlePath"] ?? "")) duplicateBundles.add(tempKext["BundlePath"] ?? "");
                    break;
                }
            }

            if (tempKext["Enabled"] == true && info != null) {
                bundlesEnabled.add(kext["BundlePath"] ?? "");
                enabledKexts.add((tempKext, info));
            }
        }

        if (duplicateBundles.isNotEmpty) {
            onLog?.call("Duplicate CFBundleIdentifiers have been disabled: ${duplicateBundles.join(", ")}");
        }

        data["Kernel"]["Add"] = orderedKexts;

        onLog?.call("All done! Finished OC ${clean ? "clean snapshot" : "snapshot"}.");
        return data;
    }

    static (KernelLimitation min, KernelLimitation max) getMinMaxFromKext(Map kext, {bool useMatch = false}) {
        if (useMatch) return getMinMaxFromMatch(kext["MatchKernel"] ?? "");
        String min = kext["MinKernel"] ?? "0.0.0";
        String max = kext["MaxKernel"] ?? "99.99.99";
        if (min.trim().isEmpty) min = "0.0.0";
        if (max.trim().isEmpty) max = "99.99.99";
        return (KernelLimitation.from(min), KernelLimitation.from(max));
    }

    static (KernelLimitation min, KernelLimitation max) getMinMaxFromMatch(String match) {
        var min = "0.0.0";
        var max = "99.99.99";
        if (match == "1") match = "";

        if (match.trim().isNotEmpty) {
            try {
                var minList = match.split(".");
                var maxList = minList.map((x) => x).toList();

                minList.addAll(List.generate(3 - minList.length, (i) => "0"));
                maxList.addAll(List.generate(3 - minList.length, (i) => "99"));

                minList.map((x) => x.isEmpty ? "0" : x);
                maxList.map((x) => x.isEmpty ? "99" : x);

                min = minList.join(".");
                max = maxList.join(".");
            } catch (_) {}
        }

        return (KernelLimitation.from(min), KernelLimitation.from(max));
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

    /// So we're not counting one of macOS's auto-generated files.
    static bool pathIsValid(String path) {
        return !path.split(".").contains("__MACOSX");
    }

    static String pathToRelative(Directory root, String path) {
        return path.startsWith(root.path) ? path.substring(root.path.length + 1) : path;
    }

    static List<String> listDirectory(Directory directory, {void Function(String) onLog = print}) {
        List<String> results = directory.listSync(recursive: true).whereType<File>().map((x) {
            return pathToRelative(directory, x.path);
        }).toList();

        onLog("Found ${results.length} files for ${p.basename(directory.path)}");
        return results;
    }

    static List<KextData> listKexts(Directory directory, {void Function(String) onLog = print}) {
        List<Directory> kexts = directory.listSync(recursive: true, followLinks: false).whereType<Directory>().where((x) => x.path.endsWith(".kext")).toList();
        onLog("Found ${kexts.length} kexts");
        return kexts.map((x) => KextData.fromDirectory(directory, x)).whereType<KextData>().toList();
    }
}

class OpenCoreVersion implements Comparable<OpenCoreVersion> {
    final bool _latest;
    bool get latest => _latest;

    final int main;
    final int sub;
    final int patch;

    OpenCoreVersion(this.main, this.sub, this.patch) : _latest = false;
    OpenCoreVersion.from(String? version) : main = int.tryParse(version?.split(".").elementAtOrNull(0) ?? "") ?? 0, sub = int.tryParse(version?.split(".").elementAtOrNull(1) ?? "") ?? 0, patch = int.tryParse(version?.split(".").elementAtOrNull(2) ?? "") ?? 0, _latest = false;
    OpenCoreVersion.latest() : _latest = true, main = 0, sub = 0, patch = 0;

    @override
    int compareTo(OpenCoreVersion other) {
        if (latest && other.latest) return 0;
        if (latest) return 1;
        if (other.latest) return -1;

        if (main != other.main) return main.compareTo(other.main);
        if (sub != other.sub) return sub.compareTo(other.sub);
        return patch.compareTo(other.patch);
    }

    bool operator <(OpenCoreVersion other) => compareTo(other) < 0;
    bool operator >(OpenCoreVersion other) => compareTo(other) > 0;
    bool operator <=(OpenCoreVersion other) => compareTo(other) <= 0;
    bool operator >=(OpenCoreVersion other) => compareTo(other) >= 0;

    @override
    bool operator ==(Object other) =>
        other is OpenCoreVersion &&
        compareTo(other) == 0 &&
        latest == other.latest;

    @override
    String toString() {
        return _latest ? "Latest" : "V. ${toRawString()}";
    }

    String toRawString() {
        return _latest ? "Latest" : [main, sub, patch].join(".");
    }
}

class KextData {
    final String name;
    final String path;
    final String infoPlistPath;
    final Map infoPlistData;
    final String? executablePath;

    const KextData({required this.name, required this.path, required this.infoPlistPath, required this.infoPlistData, required this.executablePath});

    static KextData? fromDirectory(Directory rootKextsDir, Directory directory) {
        if (!directory.existsSync() || !rootKextsDir.existsSync()) {
            print("A provided directory doesn't exist.");
            return null;
        }

        String name = p.basename(directory.path);
        File bundle = File(p.join(directory.path, "Contents", "Info.plist"));
        Map info = PlistParser().parseFileSync(bundle.path);
        File? potentialExecutable = info["CFBundleExecutable"] is String ? File(p.join(directory.path, "Contents", "MacOS", info["CFBundleExecutable"])) : null;

        if (!bundle.existsSync()) {
            print("KextData.fromDirectory: Bundle path doesn't exist for kext $name: ${bundle.path}");
            return null;
        }

        return KextData(
            name: name,
            path: OCSnapshot.pathToRelative(rootKextsDir, directory.path),
            infoPlistPath: OCSnapshot.pathToRelative(directory, bundle.path),
            infoPlistData: info,
            executablePath: (potentialExecutable?.existsSync() ?? false)
                ? OCSnapshot.pathToRelative(directory, potentialExecutable!.path)
                : null,
        );
    }
}

class KernelLimitation implements Comparable<KernelLimitation> {
    final int major;
    final int minor;
    final int patch;

    KernelLimitation.from(String? version) : major = int.tryParse(version?.split(".").elementAtOrNull(0) ?? "") ?? 0, minor = int.tryParse(version?.split(".").elementAtOrNull(1) ?? "") ?? 0, patch = int.tryParse(version?.split(".").elementAtOrNull(2) ?? "") ?? 0;

    @override
    int compareTo(KernelLimitation other) {
        if (major != other.major) return major.compareTo(other.major);
        if (minor != other.minor) return minor.compareTo(other.minor);
        return patch.compareTo(other.patch);
    }

    bool operator <(KernelLimitation other) => compareTo(other) < 0;
    bool operator >(KernelLimitation other) => compareTo(other) > 0;
    bool operator <=(KernelLimitation other) => compareTo(other) <= 0;
    bool operator >=(KernelLimitation other) => compareTo(other) >= 0;

    @override
    bool operator ==(Object other) => other is KernelLimitation && compareTo(other) == 0;
}