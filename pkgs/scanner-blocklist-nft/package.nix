{
  lib,
  fetchFromGitHub,
  python3,
  runCommand,
}:
let
  src = fetchFromGitHub {
    owner = "MISP";
    repo = "misp-warninglists";
    rev = "40e2b570fda2e5443a2d6fa1d1db16c37ab0a956";
    hash = "sha256-6FSK2G2b2WPjG4Qjuo/uZboy1+gdOayuTUAy5FQV7Rg=";
  };
in
runCommand "scanner-blocklist-nft"
  {
    nativeBuildInputs = [ python3 ];
    meta = {
      description = "nftables ruleset dropping known scanner IP ranges from MISP warninglists";
      homepage = "https://github.com/MISP/misp-warninglists";
      platforms = lib.platforms.all;
    };
  }
  ''
    python3 ${./generate.py} "${src}/lists" "$out"
  ''
