# Third-party MediaWiki extensions and skins, pinned to a single MW release.
#
# To upgrade to a new major version:
#   1. For each entry, find the latest commit on the new REL branch:
#        git ls-remote <repo-url> refs/heads/REL1_XX
#   2. Update `rev` and set `hash`/`sha256` to `lib.fakeHash`; Nix will report the correct value
{
  fetchFromGitHub,
  fetchgit,
}:
let
  # Fetch an extension mirrored on GitHub (wikimedia/mediawiki-extensions-<name>).
  mkMWExtensionGithub =
    {
      name,
      rev,
      hash,
    }:
    fetchFromGitHub {
      owner = "wikimedia";
      repo = "mediawiki-extensions-${name}";
      inherit rev hash;
    };

  # Base fetcher for Wikimedia's Gerrit instance.
  # group: "extensions" or "skins"
  fetchFromWikimedia =
    {
      group,
      repo,
      rev,
      sha256,
    }:
    fetchgit {
      url = "https://gerrit.wikimedia.org/r/mediawiki/${group}/${repo}";
      inherit rev sha256;
    };

  # Fetch a MediaWiki extension or skin from Wikimedia Gerrit.
  # Set skin = true for skins (routes to the skins/ group).
  mkMWExtension =
    {
      name,
      rev,
      sha256,
      skin ? false,
    }:
    fetchFromWikimedia {
      group = if skin then "skins" else "extensions";
      repo = name;
      inherit rev sha256;
    };
in
{
  # ── Extensions ─────────────────────────────────────────────────────────────

  Cargo = mkMWExtensionGithub {
    name = "Cargo";
    rev = "7bee551c62f5b4dba57a65fe7413987bcd7c8fef"; # REL1_45
    hash = "sha256-97r5AVkg/vZsgDmjHkKbOOLrlOQeN41Q6k+Oh4FONtU=";
  };
  CSS = mkMWExtensionGithub {
    name = "CSS";
    rev = "b3019ffcf40a3d54c1e5e0ec9989139037114a2a"; # REL1_45
    hash = "sha256-FxfgtmHI0ElXAdxMBF6B3Qn3/UqwRkF+uyoa/sFeesM=";
  };
  NoTitle = mkMWExtensionGithub {
    name = "NoTitle";
    rev = "378edc1713e4ae5e427c979cbd465dcd4c946b78"; # REL1_45
    hash = "sha256-N1oKT4Ywbg9uC1gMilGH+T3YyDIZCtiRzx3laU4N2kw=";
  };

  Popups = mkMWExtension {
    name = "Popups";
    rev = "2464e75f87b7ad7e2bc46b94b30f99ade4da8e82"; # REL1_45
    sha256 = "sha256-99fzbC0pA+GGyYYzKZB+IcT/kU0vJSkjZ8r1Xszm4SQ=";
  };

  Mermaid = fetchFromGitHub {
    owner = "SemanticMediaWiki";
    repo = "Mermaid";
    rev = "bc7363f003057888b2f0087f350fd63c172afb05"; # v6.0.2
    sha256 = "sha256-ZGNkq7CblfAcCcuZwO2W/HCF4dHF+ryiZkLHtF6L9P8=";
  };

  MobileFrontend = mkMWExtension {
    name = "MobileFrontend";
    rev = "ad2231f03b224633e8a2c82d689e61609b895dbb"; # REL1_45
    sha256 = "sha256-hYT+5OzqX9K9ZJznJoTfM/1RuHlrLBmvAK+47iaznlc=";
  };

  # ── Skins ───────────────────────────────────────────────────────────────────

  MinervaNeue = mkMWExtension {
    name = "MinervaNeue";
    skin = true;
    rev = "80632db20d84db602f35ca9c90d6a7f277ef11a8"; # REL1_45
    sha256 = "sha256-7ticKolLNO0mozHWcfMkhAwenFHnyq9kd7Sf3FQBrJk=";
  };
}
