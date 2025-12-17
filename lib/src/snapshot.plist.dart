/// This whole file is just a data dump from OCSnapshot/Scripts/snapshot.plist.
///
/// All credit here goes to CorpNewt.
library;

/// An [SnapshotData] object.
const snapshot = SnapshotData._();

/// Made so I can type [snapshot.plist] and feel cool.
// ignore: camel_case_types
class SnapshotData {
  /// OCSnapshot/Scripts/snapshot.plist.
  static List<Map<String, dynamic>> get getPlist => _plist;

  /// OCSnapshot/Scripts/snapshot.plist.
  List<Map<String, dynamic>> get plist => getPlist;

  const SnapshotData._();
}

const List<Map<String, dynamic>> _plist = [
  {
    "debug_hashes": [
      "741aee4b8f8b9c6a664de89918bc1f43",
      "08d1e112047d667968062880ec458c2b",
      "e967efcfe748a77b2dfde30bc5975202",
      "de5452ddb91f000f705cd4e840cf10dc",
      "6329c37d656fda26ba2cd71a1ebd79ff",
      "93169bfb661be0eaaff580cdfb555695",
      "dba586eea477b6dbd2d1b8e0d55d973d",
      "1cda4816c6a4ceeffe885f4143c69554",
      "34b4b04ac722f5bcf73df3053be920f3",
      "8a2ac792d093e08abb5720e1e49aaf5f",
      "b26f0dff362ccd5a9ff6263f422757af",
      "ab665d6747347e7d84111bc4eed9aa0a",
      "90522df5361813bf25bf57882693059c",
      "8668bb81d915aac49cadd1617a0eaf3b",
      "d3b8a795e1e181ff9d4b1579606141f4",
      "d7613a4070c0ba1d7d0b5803a78a5039",
      "6900c59f1a007c3ceb5180b5a6d65aef",
      "73dba3e59737eaf18904528f9167c846",
      "1670e4325df7adf5d32e62cf9abb2adf",
      "ed86ac6bb825eff2e48ec359a1a31dcc",
      "1d5cba95ef289a3b30f792b0170a259f",
      "547eb836f5db2831ed86c9769fbab658",
      "7135c321c1d28ba13adf01bdd0fa3a08"
    ],
    "kext_add": {
      "Arch": "Any",
      "MaxKernel": "",
      "MinKernel": ""
    },
    "min_version": "0.8.4",
    "release_hashes": [
      "108763df07f5fd553bcc670ddb99a290",
      "43cb036c304cc8f43015e13859407f51",
      "16eaf9fe40743aa62de8f00e3de6ec40",
      "80ccfa3ce6863fefb2c66d5a09e6c82a",
      "35738c460a4c962d57d8a5b29c5c698c",
      "a8f91e30bfb49298b7439d6eb99ce17a",
      "46f782bd98c229dbff70976633e01e65",
      "7e09a1b87e2ce09d3eed6259b7960ba5",
      "7707089aa43a1f8e1ffacb97145709bf",
      "195453e32357f16a904f87c24cba51fe",
      "b967a0a6189175376b32e9e2ae79848a",
      "0cbf167281f9fcf64316c55fcfa8dbd4",
      "bd68d62b4a39168746b4cfc9197fd452",
      "4d1e53334a8bb41b11ca41d9c08843bd",
      "47be19f160e9f80f35093e813af51aa4",
      "f9d47e038dc3e9a97781879eea495f63",
      "d3c7f7652dfc4d811153de2c9a85fdbe",
      "93bb05febe9b6a34e3dcd36f26aaf16a",
      "ba1d246b8abfa59e0b56615f2f5caada",
      "44a58f86045ad4c0783bdb78b9e21c2e",
      "fd45ddeb808efd977ac0fbeb549286ec",
      "ebe83ed9e53fba523af024f31ee55605",
      "d6567203f0d222a026b5ecfcbaea81c4"
    ],
    "tool_add": {
      "Arguments": "",
      "Auxiliary": true,
      "Flavour": "Auto",
      "FullNvramAccess": false,
      "RealPath": false,
      "TextMode": false
    },
    "driver_add": {
      "Arguments": "",
      "Comment": "",
      "LoadEarly": false
    }
  },
  {
    "debug_hashes": [
      "f253ef64ed271d3c95ece553844a34b4"
    ],
    "kext_add": {
      "Arch": "Any",
      "MaxKernel": "",
      "MinKernel": ""
    },
    "min_version": "0.8.3",
    "max_version": "0.8.3",
    "release_hashes": [
      "9026dd50835d644084d583c340ccdd82"
    ],
    "tool_add": {
      "Arguments": "",
      "Auxiliary": true,
      "Flavour": "Auto",
      "RealPath": false,
      "TextMode": false
    },
    "driver_add": {
      "Arguments": "",
      "Comment": "",
      "LoadEarly": false
    }
  },
  {
    "debug_hashes": [
      "95497990f2dde60661ec66c57f55a28b",
      "5be2c6ee90d95f786e8d511ce2124055",
      "a0f63021d1605fe580eea882f3760823",
      "7c09a5bd5c1554881b0acd1594b971be",
      "7de24a3b50a581765a211fa45055214b",
      "972daa56413cfe7f5bab31dbb6ccc68c",
      "f99d91e4be938766f16768b60773be72",
      "31800acd3d80d77539ce21064bea79ef",
      "c08d55614715485e2b096e175aae13b3"
    ],
    "kext_add": {
      "Arch": "Any",
      "MaxKernel": "",
      "MinKernel": ""
    },
    "min_version": "0.7.4",
    "max_version": "0.8.2",
    "release_hashes": [
      "81a2ac329da9548da0ab0cb140eb9661",
      "f4ee8bbaf27fcb34367d6192b5db1eec",
      "e8a18dd8bc56ade19eee855d3caad928",
      "236d5622b556c56888dae3410dbcf2de",
      "25b357c3b0d7842e1bb99c18d1367fc0",
      "4b92f0e0291ce0cc0db9716ac0ed2724",
      "d032ab8e6ca3fcbd1614208423428a38",
      "6792be19b704d7346e68587dc1b01209",
      "f0b718f48792286204e95cf2189a6273"
    ],
    "tool_add": {
      "Arguments": "",
      "Auxiliary": true,
      "Flavour": "Auto",
      "RealPath": false,
      "TextMode": false
    },
    "driver_add": {
      "Arguments": "",
      "Comment": ""
    }
  },
  {
    "debug_hashes": [
      "bda0fed36bdb3301c1b788f8259c74fe"
    ],
    "kext_add": {
      "Arch": "Any",
      "MaxKernel": "",
      "MinKernel": ""
    },
    "min_version": "0.7.3",
    "max_version": "0.7.3",
    "release_hashes": [
      "95a3f5b7df5e3aee7f44588d56fe1cd3"
    ],
    "tool_add": {
      "Arguments": "",
      "Auxiliary": true,
      "Flavour": "Auto",
      "RealPath": false,
      "TextMode": false
    },
    "driver_add": {
      "Arguments": ""
    }
  },
  {
    "debug_hashes": [
      "26f6d78711ec93afededcee86abe7c8d",
      "9001a6107a0db056e896cf68c26471c8",
      "9848c07e173aa448ea701b3ed0e210b5"
    ],
    "kext_add": {
      "Arch": "Any",
      "MaxKernel": "",
      "MinKernel": ""
    },
    "min_version": "0.7.0",
    "max_version": "0.7.2",
    "release_hashes": [
      "67406c9656c353aa8919c8930c897c3c",
      "1160d5af5f29ef17c2c870862f2a4728",
      "1314c4f3220539d997637fa0b57026b5"
    ],
    "tool_add": {
      "Arguments": "",
      "Auxiliary": true,
      "Flavour": "Auto",
      "RealPath": false,
      "TextMode": false
    }
  },
  {
    "debug_hashes": [
      "f23d2a4dab95b33907f42f7270d78ac4",
      "63296f1dd2e65459bdece8c9634e19c2",
      "71309b1a64eb1532102eb449eece47bf",
      "01ed550d56ace511e31e447bb26b85f0",
      "7839b1ff468f88d552703d6cf04d427a",
      "5b8545e031bd9341f7bc20fe313cc390"
    ],
    "kext_add": {
      "Arch": "Any",
      "MaxKernel": "",
      "MinKernel": ""
    },
    "max_version": "0.6.9",
    "min_version": "0.6.4",
    "release_hashes": [
      "5e39db9a6525e4985d20fb3a0f647d7f",
      "146d835a6ca1af0e43fb5c14274004fc",
      "a29f8e0bb2622799b5f50e63d2587382",
      "d52d02c34833ed1e02880a6bad6ba620",
      "7451af0a43fe1c87f2c5e46627070337",
      "33dc9e8185b66f4ab466890590011351"
    ],
    "tool_add": {
      "Arguments": "",
      "Auxiliary": true,
      "RealPath": false,
      "TextMode": false
    }
  },
  {
    "debug_hashes": [
      "8ef8d1803e91c6718dfee59408b6a468",
      "86652faf1a336a446b187ae283d2cc9a",
      "aee0e2713f267fa907bb4e1250af71f7"
    ],
    "kext_add": {
      "Arch": "Any",
      "MaxKernel": "",
      "MinKernel": ""
    },
    "max_version": "0.6.3",
    "min_version": "0.6.1",
    "release_hashes": [
      "3255c15833abcb05789af00c0e50bf82",
      "f6bcc6d06d95a1e657e61a15666cde9f",
      "19758cfb7f8f157959bf608fc76a069d"
    ],
    "tool_add": {
      "Arguments": "",
      "Auxiliary": true
    }
  },
  {
    "debug_hashes": [
      "db78c5fef3550213e947b8d6fa5338e4",
      "88e8aec480eb24e757241580731d2023",
      "b85c28aa004291a96bf74d95eea3364a",
      "f46456574b8b67f603de74c201b4e130",
      "f663a56f66b9d95fd053a46b0829fa5c"
    ],
    "kext_add": {
      "MaxKernel": "",
      "MinKernel": ""
    },
    "max_version": "0.6.0",
    "min_version": "0.5.6",
    "release_hashes": [
      "947f8ccfec961d02f54d1a2f5c808504",
      "3e99e56bc16ed23129b3659a3d536ae9",
      "dd2bb459dfbb1fe04ca0cb61bb8f9581",
      "da4a5e54641317b2aa7715f8b4273791",
      "5010a4db83dacbcc14b090e00472c661"
    ],
    "tool_add": {
      "Arguments": "",
      "Auxiliary": true
    }
  },
  {
    "debug_hashes": [
      "4be8a2620c923129b3bac0b2d1b8fd6b",
      "52f819181055f501b6882c2a73268dbc",
      "1d821f7a51eab7c39999328438770fa7",
      "d36cb1eafafcd9b94d3526aece5bc8b4",
      "217a07b161306324d147681914a319c3"
    ],
    "kext_add": {
      "MaxKernel": "",
      "MinKernel": ""
    },
    "max_version": "0.5.5",
    "min_version": "0.5.1",
    "release_hashes": [
      "ff42893722bc0a3278c7d8029b797342",
      "ba2a5846697e7895753e7b05989738e5",
      "8cc62a1017afa01c2c75ad4b6fca8df2",
      "21aa72da926ec362ab58626b60c36ac8",
      "4bdb27730c0c06275e2fc389348d46d0"
    ],
    "tool_add": {
      "Arguments": ""
    }
  },
  {
    "debug_hashes": [
      "ec0e6c7dfa2ab84eaad52f167e85466f"
    ],
    "kext_add": {
      "MatchKernel": ""
    },
    "max_version": "0.5.0",
    "min_version": "0.5.0",
    "release_hashes": [
      "081f9922be27b2d1e82fc8dbd3426498"
    ]
  }
];