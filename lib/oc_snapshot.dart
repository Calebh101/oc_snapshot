/// This library contains methods for doing an OC snapshot in Dart, ported from CorpNewt's ProperTree.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:oc_snapshot/src/snapshot.plist.dart';
import 'package:path/path.dart' as p;
import 'package:plist_parser/plist_parser.dart';
import 'package:xml/xml.dart';

/// Base class containing multiple methods of this package.
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
    /// [onLog] is called when the package wants to log something. It can be set to null, but you can also make it use either [print] or a custom logging solution. It defaults to [print].
    static Map snapshot(Map data, {
        bool clean = false,
        bool forceUpdateSchema = false,
        OpenCoreVersion? opencoreVersion,
        String? opencoreHash,
        void Function(String)? onLog = print,

        // File paths, relative to the `ACPI`, `Kexts`, `Drivers`, and `Tools` folders respectively.
        required ({List<String> acpi, List<KextData> kexts, List<String> drivers, List<String> tools}) files,
    }) {
        Map? latestSnapshot;
        Map? targetSnapshot;
        Map? selectedSnapshot;

        // Time to determine the snapshot to use
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

        // Time to do ACPI blah
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

        // Time to do kexts stuff (this is nightmare fuel)
        if (data["Kernel"] is! Map) data["Kernel"] = {"Add": []};
        if (data["Kernel"]["Add"] is! List) data["Kernel"]["Add"] = [];

        List<(Map<String, dynamic> infoPlist, Map<String, dynamic> kinfo)> kextList = [];
        List<String> omittedKexts = [];

        for (var kext in files.kexts) {
            if (!pathIsValid(kext.path)) continue;
            if (p.basename(kext.path).startsWith(".")) continue;
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
                final value = match.$1[check];
                if (value is String && value.isNotEmpty) kext[check] = value;
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
        // Wow that took a while

        // Time to do tools stuff
        if (data["Misc"] is! Map) data["Misc"] = {"Tools": []};
        if (data["Misc"]["Tools"] is! List) data["Misc"]["Tools"] = [];

        List<Map> toolsList = [];

        for (var tool in files.tools) {
            if (!pathIsValid(tool)) continue;
            if (p.basename(tool).startsWith(".")) continue;
            if (!tool.endsWith(".efi")) continue;

            Map<String, dynamic> entry = {
                "Name": p.basename(tool),
                "Path": tool,
                "Comment": p.basename(tool),
                "Enabled": true,
            };

            for (var e in snapshotToolsAdd.entries) {
                if (e.key == "Flavour" && tool.toLowerCase().endsWith("shell.efi")) {
                    entry[e.key] == "OpenShell:UEFIShell:Shell";
                } else {
                    entry[e.key] == snapshotToolsAdd[e.key];
                }
            }

            toolsList.add(entry);
        }

        List tools = clean ? [] : data["Misc"]["Tools"];
        tools.sort((a, b) => (a["Path"] as String? ?? "").compareTo((b["Path"] as String? ?? "").toLowerCase()));

        for (var tool in tools) {
            if (tools.whereType<Map>().map((x) => (x["Path"]?.toString() ?? "").toLowerCase()).contains((tool["Path"]?.toString() ?? "").toLowerCase())) continue;
            tools.add(tool);
        }

        List<Map> newTools = [];

        for (var tool in tools.whereType<Map>()) {
            if (!toolsList.whereType<Map>().map((x) => (x["Path"]?.toString() ?? "").toLowerCase()).contains((tool["Path"]?.toString() ?? "").toLowerCase())) continue; // Not there
            newTools.add(tool);
            longPaths.addAll(checkPathLength(tool, "Tools\\"));
        }

        List<String> toolsEnabled = [];
        List<String> toolsDuplicates = [];
        List<Map> toolsDuplicatesDisabled = [];

        for (var tool in newTools) {
            if (tool["Enabled"] == true) {
                if (toolsEnabled.contains(tool["Path"] ?? "")) {
                    var newTool = {};
                    for (var k in tool.keys) newTool[k] = tool[k];
                    newTool["Enabled"] = false;
                    toolsDuplicatesDisabled.add(newTool);

                    if (!toolsDuplicates.contains(tool["Path"] ?? "")) {
                        toolsDuplicates.add(tool["Path"] ?? "");
                    }
                } else {
                    toolsEnabled.add(tool["Path"] ?? "");
                    toolsDuplicatesDisabled.add(tool);
                }
            }
        }

        if (toolsDuplicates.isNotEmpty) {
            onLog?.call("Duplicate tools have been disabled: ${toolsDuplicates.join(", ")}");
            newTools = toolsDuplicatesDisabled;
        }

        data["Misc"]["Tools"] = newTools;

        // Almost done! Now just the drivers, this won't be bad, right?
        if (data["UEFI"] is! Map) data["UEFI"] = {"Drivers": []};
        if (data["UEFI"]["Drivers"] is! List) data["UEFI"]["Drivers"] = [];

        List driversList = [];

        for (var driver in files.drivers) {
            if (!pathIsValid(driver)) continue;
            if (p.basename(driver).startsWith(".")) continue;
            if (!driver.endsWith(".efi")) continue;

            if (snapshotDriversAdd.isEmpty) {
                driversList.add(driver);
            } else {
                var entry = {
                    "Enabled": true,
                    "Path": driver,
                };

                for (var x in snapshotDriversAdd.entries) {
                    entry[x.key] = x.key.toLowerCase() == "Comment" ? p.basename(driver) : snapshotDriversAdd[x.key];
                    driversList.add(entry);
                }
            }
        }

        List drivers = clean ? [] : data["UEFI"]["Drivers"];
        drivers.sort((a, b) => (a["Path"] as String? ?? "").compareTo((b["Path"] as String? ?? "").toLowerCase()));

        for (var driver in driversList) {
            if (snapshotDriversAdd.isEmpty) {
                if (driver is! String || drivers.whereType<String>().map((x) => x.toLowerCase()).contains(driver.toLowerCase())) continue;
            } else {
                if (drivers.whereType<Map>().map((x) => (x["Path"]?.toString() ?? "").toLowerCase()).contains((driver["Path"]?.toString() ?? "").toLowerCase())) continue;
            }

            drivers.add(driver);
        }

        List newDrivers = [];

        for (var driver in drivers) {
            if (snapshotDriversAdd.isEmpty) {
                if (driver is! String || !driversList.whereType<String>().map((x) => x.toLowerCase()).contains(driver.toLowerCase())) continue;
            } else {
                if (driver is! Map) continue;
                if (!driversList.map((x) => x["Path"]?.toString().toLowerCase() ?? "").contains(driver["Path"]?.toString().toLowerCase())) continue;
            }

            newDrivers.add(driver);
            longPaths.addAll(checkPathLength(driver, "\\Drivers"));
        }

        List driversEnabled = [];
        List driversDuplicates = [];
        List driversDuplicatesDisabled = [];

        for (var d in newDrivers) {
            if (d is Map) {
                if (d["Enabled"] == true) {
                    if (driversEnabled.contains(d["Path"] ?? "")) {
                        Map<dynamic, dynamic> newD = {};
                        for (var k in d.keys) newD[k] = d[k];
                        newD["Enabled"] = false;
                        if (!driversDuplicates.contains(d["Path"] ?? "")) driversDuplicatesDisabled.add(newD);
                    } else {
                        driversEnabled.add(d["Path"] ?? "");
                        driversDuplicatesDisabled.add(d);
                    }
                }
            } else if (d is String) {
                if (driversEnabled.contains(d)) {
                    if (!driversDuplicates.contains(d)) {
                        driversDuplicates.add(d);
                    }
                } else {
                    driversEnabled.add(d);
                    driversDuplicatesDisabled.add(d);
                }
            }
        }

        if (driversDuplicates.isNotEmpty) {
            onLog?.call("Duplicate drivers have been disabled: ${driversDuplicates.join(", ")}");
        }

        data["UEFI"]["Drivers"] = newDrivers;

        if (forceUpdateSchema) {
            onLog?.call("Forcing snapshot schema update...");
            var ignored = ["Comment", "Enabled", "Path", "BundlePath", "ExecutablePath", "PlistPath", "Name"];

            for (var entry in [
                (data["ACPI"]["Add"] as List<Map>, snapshotAcpiAdd),
                (data["Kernel"]["Add"] as List<Map>, snapshotKextsAdd),
                (data["Misc"]["Tools"] as List<Map>, snapshotToolsAdd),
                (data["UEFI"]["Drivers"] as List<Map>, snapshotDriversAdd),
            ]) {
                final List<Map> entries = entry.$1;
                final Map values = entry.$2;

                values["Comment"] = "";
                values["Enabled"] = true;
                if (values.isEmpty) continue;

                for (var entry in entries) {
                    var toRemove = entry.entries.where((x) => !values.containsKey(x.key) && !ignored.contains(x.key)).map((x) => x.key);
                    var toAdd = values.entries.where((x) => !entry.containsKey(x)).map((x) => x.key);

                    for (var add in toAdd) {
                        late dynamic value;

                        if (add.toLowerCase() == "comment") {
                            p.basename(entry["Path"] ?? entry["BundlePath"] ?? values[add] ?? "Unknown");
                        } else {
                            value = values[add];
                        }

                        entry[add] = value;
                    }

                    for (var r in toRemove) {
                        entry.remove(r);
                    }
                }
            }
        }

        if (longPaths.isNotEmpty) {
            var formatted = [];

            for (var entry in longPaths) {
                if (entry.item is String) {
                    formatted.add(entry.name);
                } else if (entry.item is Map) {
                    formatted.add("${entry.name} -> ${entry.pathsTooLong.join(", ")}");
                }

                onLog?.call("The following file paths have been found to exceed the $safePathLength-character safe path max declared by OpenCore, and may not work as intended:\n${formatted.join(", ")}");
            }
        }

        onLog?.call("All done! Finished OC ${clean ? "clean snapshot" : "snapshot"}.");
        return data;
    }

    /// Try to parse the MinKernel/MaxKernel values from a kext dictionary.
    static (KernelLimitation min, KernelLimitation max) getMinMaxFromKext(Map kext, {bool useMatch = false}) {
        if (useMatch) return getMinMaxFromMatch(kext["MatchKernel"] ?? "");
        String min = kext["MinKernel"] ?? "0.0.0";
        String max = kext["MaxKernel"] ?? "99.99.99";
        if (min.trim().isEmpty) min = "0.0.0";
        if (max.trim().isEmpty) max = "99.99.99";
        return (KernelLimitation.from(min), KernelLimitation.from(max));
    }

    /// Try to parse the MinKernel/MaxKernel values from a match.
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

    /// If a path is too long (including prefix), then we return it enclosed in a list. Otherwise, return a blank list.
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

    /// Turn an absolute path into a path relative to the inputted [root].
    ///
    /// If [path] does not contain [root], [path] is returned unchanged.
    static String pathToRelative(Directory root, String path) {
        return path.startsWith(root.path) ? path.substring(root.path.length + 1) : path;
    }

    /// This lists the files of a directory recursively. This will then return a list of *relative* file paths.
    static List<String> listDirectory(Directory directory, {void Function(String)? onLog = print}) {
        List<String> results = directory.listSync(recursive: true).whereType<File>().map((x) {
            return pathToRelative(directory, x.path);
        }).toList();

        onLog?.call("Found ${results.length} files for ${p.basename(directory.path)}");
        return results;
    }

    /// A version of [listDirectory], but for kexts.
    /// Here, instead of listing all files, we just find all directories that end with `.kext`, then process them.
    static List<KextData> listKexts(Directory directory, {void Function(String)? onLog = print}) {
        List<Directory> kexts = directory.listSync(recursive: true, followLinks: false).whereType<Directory>().where((x) => x.path.endsWith(".kext")).toList();
        onLog?.call("Found ${kexts.length} kexts");
        return kexts.map((x) => KextData.fromDirectory(directory, x)).whereType<KextData>().toList();
    }

    /// A custom function to turn an [Object] into a plist.
    ///
    /// [showNull] will make null values have a `<null/>` tag.
    ///
    /// [prettyIndent] judges if the outputted string should be formatted or not. If this is null or less than 1, then the output will not be formatted.
    static String toPlist(Object? input, {bool showNull = false, int? prettyIndent = 4, void Function(String)? onLog}) {
        XmlNode? process(Object? value) {
            if (value == null) {
                return showNull ? XmlElement(XmlName("null")) : null;
            } else if (value is String) {
                return XmlElement(XmlName("string"), [], [XmlText(value)]);
            } else if (value is int) {
                return XmlElement(XmlName("integer"), [], [XmlText(value.toString())]);
            } else if (value is double) {
                return XmlElement(XmlName("real"), [], [XmlText(value.toString())]);
            } else if (value is bool) {
                return XmlElement(XmlName(value ? "true" : "false"));
            } else if (value is DateTime) {
                return XmlElement(XmlName("date"), [], [XmlText(value.toUtc().toIso8601String())]);
            } else if (value is Uint8List) {
                final text = base64Encode(value);
                return XmlElement(XmlName("data"), [], [XmlText(text)]);
            } else if (value is List) {
                return XmlElement(XmlName("array"), [], value.map((x) => process(x)).whereType<XmlNode>());
            } else if (value is Map) {
                List<XmlNode> children = [];

                value.forEach((key, value) {
                XmlNode? node = process(value);

                if (node != null) {
                    children.add(XmlElement(XmlName("key"), [], [XmlText(key)]));
                    children.add(node);
                }
                });

                return XmlElement(XmlName("dict"), [], children);
            } else {
                onLog?.call("Warning: Invalid plist type: ${value.runtimeType}");
                return null;
            }
        }

        XmlBuilder builder = XmlBuilder();
        builder.processing('xml', 'version="1.0" encoding="UTF-8"');

        builder.element('plist', nest: () {
            builder.attribute('version', '1.0');
        });

        XmlDocument document = builder.buildDocument();
        document.rootElement.children.add(process(input)!);
        bool pretty = prettyIndent != null && prettyIndent > 0;

        return document.toXmlString(
            pretty: pretty,
            indent: pretty ? " " * prettyIndent : null,
            newLine: pretty ? "\n" : null,
        );
    }
}

/// A class that represents a specific version of OpenCore, or the latest in general.
///
/// - 1.0.6: [main].[sub].[patch]
/// - Latest: [latest] is true
class OpenCoreVersion implements Comparable<OpenCoreVersion> {
    final bool _latest;

    /// Main version number.
    final int main;

    /// Second version number.
    final int sub;

    /// Last version number.
    final int patch;

    /// If this [OpenCoreVersion] represents the latest OpenCore in general.
    bool get latest => _latest;

    /// A class that represents a specific version of OpenCore, or the latest in general.
    ///
    /// - 1.0.6: [main].[sub].[patch]
    /// - Latest: [latest] is true
    OpenCoreVersion(this.main, this.sub, this.patch) : _latest = false;

    /// Return an [OpenCoreVersion] from an inputted string. Sections that can't be parsed default to 0.
    OpenCoreVersion.from(String? version) : main = int.tryParse(version?.split(".").elementAtOrNull(0) ?? "") ?? 0, sub = int.tryParse(version?.split(".").elementAtOrNull(1) ?? "") ?? 0, patch = int.tryParse(version?.split(".").elementAtOrNull(2) ?? "") ?? 0, _latest = false;

    /// The latest OpenCore in general.
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

    /// This [OpenCoreVersion] is less than the other [OpenCoreVersion].
    bool operator <(OpenCoreVersion other) => compareTo(other) < 0;

    /// This [OpenCoreVersion] is greater than the other [OpenCoreVersion].
    bool operator >(OpenCoreVersion other) => compareTo(other) > 0;

    /// This [OpenCoreVersion] is less than or equal to the other [OpenCoreVersion].
    bool operator <=(OpenCoreVersion other) => compareTo(other) <= 0;

    /// This [OpenCoreVersion] is greater than or equal to the other [OpenCoreVersion].
    bool operator >=(OpenCoreVersion other) => compareTo(other) >= 0;

    @override
    bool operator ==(Object other) =>
        other is OpenCoreVersion &&
        compareTo(other) == 0 &&
        latest == other.latest;

    @override
    int get hashCode => Object.hash(latest, main, sub, patch);

    @override
    String toString() {
        return _latest ? "Latest" : "V. ${toRawString()}";
    }

    /// Either `Latest` or [main].[sub].[patch].
    String toRawString() {
        return _latest ? "Latest" : [main, sub, patch].join(".");
    }
}

/// Represents a kext and its data.
class KextData {
    /// The name of the kext (including `.kext`).
    final String name;

    /// The relative path of the kext in the `Kexts` folder.
    final String path;

    /// The path to its `Info.plist`, relative to the bundle path.
    final String infoPlistPath;

    /// The loaded data in its `Info.plist`.
    final Map infoPlistData;

    /// The optional path to its executable, relative to the bundle path.
    final String? executablePath;

    /// Represents a kext and its data.
    const KextData({required this.name, required this.path, required this.infoPlistPath, required this.infoPlistData, required this.executablePath});

    /// Try to get a kext's info from a passed directory.
    ///
    /// [rootKextsDir] should be the directory of `EFI/OC/Kexts`, and [directory] should be the directory of the actual kext itself.
    static KextData? tryFromDirectory(Directory rootKextsDir, Directory directory) {
        try {
            return fromDirectory(rootKextsDir, directory);
        } catch (e) {
            return null;
        }
    }


    /// Get a kext's info from a passed directory.
    ///
    /// [rootKextsDir] should be the directory of `EFI/OC/Kexts`, and [directory] should be the directory of the actual kext itself.
    static KextData fromDirectory(Directory rootKextsDir, Directory directory) {
        if (!directory.existsSync() || !rootKextsDir.existsSync()) {
            throw NotFoundException("A provided directory doesn't exist.");
        }

        String name = p.basename(directory.path);
        File bundle = File(p.join(directory.path, "Contents", "Info.plist"));
        Map info = PlistParser().parseFileSync(bundle.path);
        File? potentialExecutable = info["CFBundleExecutable"] is String ? File(p.join(directory.path, "Contents", "MacOS", info["CFBundleExecutable"])) : null;

        if (!bundle.existsSync()) {
            throw NotFoundException("KextData.fromDirectory: Bundle path doesn't exist for kext $name: ${bundle.path}");
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

/// A class representing a kernel version for MinKernel/MaxKernel values.
class KernelLimitation implements Comparable<KernelLimitation> {
    /// Major version number.
    final int major;

    /// Minor version number.
    final int minor;

    /// Last version number.
    final int patch;

    /// Parse from a string. Any section that cannot be parsed will default to 0.
    KernelLimitation.from(String? version) : major = int.tryParse(version?.split(".").elementAtOrNull(0) ?? "") ?? 0, minor = int.tryParse(version?.split(".").elementAtOrNull(1) ?? "") ?? 0, patch = int.tryParse(version?.split(".").elementAtOrNull(2) ?? "") ?? 0;

    @override
    int compareTo(KernelLimitation other) {
        if (major != other.major) return major.compareTo(other.major);
        if (minor != other.minor) return minor.compareTo(other.minor);
        return patch.compareTo(other.patch);
    }

    /// This [KernelLimitation] is less than the other [KernelLimitation].
    bool operator <(KernelLimitation other) => compareTo(other) < 0;

    /// This [KernelLimitation] is greater than the other [KernelLimitation].
    bool operator >(KernelLimitation other) => compareTo(other) > 0;

    /// This [KernelLimitation] is less than or equal to the other [KernelLimitation].
    bool operator <=(KernelLimitation other) => compareTo(other) <= 0;

    /// This [KernelLimitation] is greater than or equal to the other [KernelLimitation].
    bool operator >=(KernelLimitation other) => compareTo(other) >= 0;

    @override
    bool operator ==(Object other) => other is KernelLimitation && compareTo(other) == 0;

    @override
    int get hashCode => Object.hash(major, minor, patch);
}