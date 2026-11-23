{ pkgs, ... }:
let
  python = pkgs.python3.withPackages (
    _: with pkgs.python3Packages; [
      httpx
      requests
      cryptography
      pycryptodome
      beautifulsoup4
      lxml
      pyyaml
      pillow
      rich
      click
      ipython
    ]
  );
in
{
  home.packages = with pkgs; [
    python
    uv
    jq
    yq-go
    ripgrep
    fd
    file
    patchelf
    mitmproxy
  ];
}
