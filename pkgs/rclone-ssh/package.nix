{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "rclone-ssh";
  version = "0.1.0";

  src = ../../src/rclone-ssh;

  vendorHash = null; # pure Go, no external dependencies

  meta = with lib; {
    description = "Rclone wrapper with transparent SSH config integration";
    license = licenses.mit;
    mainProgram = "rclone-ssh";
  };
}
