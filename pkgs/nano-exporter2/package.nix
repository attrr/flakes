{
  lib,
  stdenv,
  fetchFromGitHub,
}:
stdenv.mkDerivation {
  pname = "nano-exporter2";
  version = "2.1.0";

  src = fetchFromGitHub {
    owner = "leahneukirchen";
    repo = "nano-exporter2";
    rev = "94013d533404d1bbaddd1ad0f4aa6eaed9a24275";
    hash = "sha256-n+t5k5h3fvNeoVhNV4kbFyVemGUgRvB7Augt7WjVfuM=";
  };

  makeFlags = [
    "CC=${stdenv.cc.targetPrefix}cc"
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 nano-exporter "$out/bin/nano-exporter"
    runHook postInstall
  '';

  meta = {
    description = "Minimalistic Prometheus node metrics exporter in pure C";
    homepage = "https://github.com/leahneukirchen/nano-exporter2";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "nano-exporter";
  };
}
