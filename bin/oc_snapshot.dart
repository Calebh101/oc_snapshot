import 'package:args/args.dart';

void main(List<String> arguments) {
  ArgParser parser = ArgParser()
    ..addOption("in", help: "The path to your config.plist.", mandatory: true)
    ..addOption("out", help: "The path to where you want to write the results. This defaults to your in path.")
    ..addOption("oc", help: "The path to your OC folder in your EFI.", mandatory: true);
}