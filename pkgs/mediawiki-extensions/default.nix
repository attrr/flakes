# Third-party MediaWiki extensions and skins, pinned to a single MW release.
#
# To upgrade to a new major version:
#   1. For each entry, find the latest commit on the new REL branch:
#        git ls-remote <repo-url> refs/heads/REL1_XX
#   2. Update `rev` and set `hash`/`sha256` to `lib.fakeHash`; Nix will report the correct value
{ fetchFromGitHub, fetchgit }:
let
  # Fetch an extension mirrored on GitHub (wikimedia/mediawiki-extensions-<name>).
  mkMWExtensionGithub =
    { name, rev, hash }:
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
    rev = "5f87d10602a2504c6a0e34c86a4955110b7ed49b"; # REL1_44 @ 2026-04-14
    hash = "sha256-F1vPo9Tmb+D4AMU77CTm7w3jfJ8Ra2U0133XODWpEjI=";
  };
  CSS = mkMWExtensionGithub {
    name = "CSS";
    rev = "0fbcf5e12c6472cda53b9947b68dfbce273fc4be"; # REL1_44 @ 2026-04-14
    hash = "sha256-+Jjt5c1cEObQN9/s1ipPxviAfGeoq2vSHSjwzbiR5PI=";
  };
  NoTitle = mkMWExtensionGithub {
    name = "NoTitle";
    rev = "af73305d20a6c7708e6e749ef2ead2db342f3ea6"; # REL1_44 @ 2026-04-14
    hash = "sha256-7DAFNTJWthas5n2haUEzKu/nNsEGuFbaFCgTHFg9UkQ=";
  };

  MobileFrontend = mkMWExtension {
    name = "MobileFrontend";
    rev = "9452affdab5703d6b2c2ce3a6575505a8d90bd62"; # REL1_44 @ 2026-04-14
    sha256 = "sha256-GCgvM4y+uP+0IycKe+3hA3FZyY2/BLdT8Y7uI6EbJeA=";
  };

  # ── Skins ───────────────────────────────────────────────────────────────────

  MinervaNeue = mkMWExtension {
    name = "MinervaNeue";
    skin = true;
    rev = "7ca7bf4076cb9151b37dbaf267b025a588386413"; # REL1_44 @ 2026-04-14
    sha256 = "sha256-CgxQ7kWvtZ2s8HoBM/xY+0O+xmbb/WpsAsNObJc70JE=";
  };
}
