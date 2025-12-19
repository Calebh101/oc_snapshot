# oc_snapshot

This Dart package is a port of CorpNewt's [OCSnapshot](https://github.com/corpnewt/OCSnapshot). It supports both CLI use and Dart use.

## CLI

Use `dart pub global activate oc_snapshot` to install. To run, use the `oc_snapshot` command. Usage:

```
-h, --help                   Show this help message.
    --in                     The path to your config.plist.
    --out                    The path to where you want to write the results. This defaults to your in path.
    --oc (mandatory)         The path to your OC folder in your EFI.
    --oc-version             The OpenCore version for schema stuff. Example: 1.0.6
-c, --clean                  Clean snapshot. See README.md for more info.
-f, --force-update-schema    Add missing or remove erroneous keys from existing snapshot entries.
```

## Dart

First, add this package and import `package:oc_snapshot/oc_snapshot.dart`. After that, you'll use the `OCSnapshot` class for the OC snapshotting stuff.

Use `OCSnapshot.snapshot` to snapshot. It has quite a few arguments, but that's what DartDocs are for. There are a lot of static helper functions in `OCSnapshot` that might come in handy for serializing and transforming data into something the package can use:

- `pathIsValid` makes sure that a path doesn't contain `__MACOSX` because of pesky macOS.
- `pathToRelative` makes an absolute path relative to a specific directory. If the specified directory isn't included in the path, then nothing is changed.
- `listDirectory` lists an ACPI, Drivers, or Tools directory for all files recursively, and turns them into relative paths.
- `listKexts` is a version of `listDirectory`, but specifically for kexts because kexts are technically folders.
- `toPlist` will turn data inputted into it into a plist, with some optional things like indenting and such.

There are also some extra classes:
- `OpenCoreVersion`, which, surprise, specifies a version of OpenCore. You can  use the default constructor, `OpenCoreVersion.from` for parsing from a string (pieces unable to be parsed will default to 0), and `OpenCoreVersion.latest` for just specifying the latest OpenCore in general.
- `KextData` is a class that contains data about a kext. This is used because kext's aren't just files when snapshotting; kexts also have an `Info.plist` file that is used. You can call the default constructor, but `KextData.fromDirectory` and `KextData.tryFromDirectory` also exist for ease of use.
- `KernelLimitation` is used internally, but it defines a kernel version for min/max values.