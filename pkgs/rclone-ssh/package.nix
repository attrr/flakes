{
  lib,
  buildGoModule,
  makeWrapper,
  rclone,
}:

buildGoModule {
  pname = "rclone-ssh";
  version = "0.1.0";

  src = ../../src/rclone-ssh;

  vendorHash = null; # pure Go, no external dependencies

  nativeBuildInputs = [ makeWrapper ];

  # ssh stays the user's own, for their ssh config
  postFixup = ''
    wrapProgram $out/bin/rclone-ssh --prefix PATH : ${lib.makeBinPath [ rclone ]}
  '';

  meta = with lib; {
    description = "Rclone wrapper with transparent SSH config integration";
    license = licenses.mit;
    mainProgram = "rclone-ssh";
  };
}
