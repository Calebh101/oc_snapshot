# oc_snapshot

This Dart package is a port of CorpNewt's [OCSnapshot](https://github.com/corpnewt/OCSnapshot). It supports both CLI use and Dart use.

## CLI

Use `dart pub global activate oc_snapshot` to install. To run, use `oc_snapshot`. Usage:

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

TODO