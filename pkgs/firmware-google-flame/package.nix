{
  lib,
  stdenvNoCC,
  fetchFromGitLab,
  fetchurl,
}:

# pmaports' firmware-google-flame (2-r0): its file list, with the postmarketos/
# overrides moved to their real paths. They stay uncompressed, so the kernel
# finds them before linux-firmware's compressed copies of the same names.
# Plus the CS40L25A haptics' DSP firmware and wavetable, which pmaports
# leaves out, from stock's /vendor/firmware (LineageOS's flame vendor repo)
let
  vendorFirmware =
    name: hash:
    fetchurl {
      url = "https://raw.githubusercontent.com/TheMuppets/proprietary_vendor_google_flame/cd3677961ff7a2743cd6515650413fac35867bed/proprietary/vendor/firmware/${name}";
      inherit hash;
    };
  haptics = {
    "cs40l25a.wmfw" = vendorFirmware "cs40l25a.wmfw" "sha256-DuBs7I533BVBoOJKV8nif8n3SVwegSySHk3JnDUB9VQ=";
    "cs40l20.bin" = vendorFirmware "cs40l20.bin" "sha256-JXU5AMMSf2va3k3bw47St5rW5Rdgo8Knly6Rlt/k9Tg=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "firmware-google-flame";
  version = "2";

  src = fetchFromGitLab {
    domain = "gitlab.nura.eco";
    owner = "andrewgigena";
    repo = "firmware-google-flame";
    rev = "f25f967d19a2f5cee5906bfce313ce734007a6be";
    hash = "sha256-06SFukpya8cEuPgAIbkjoGuZ6XU1p7t2G5ACrZMqD1c=";
  };

  installPhase = ''
    runHook preInstall
    for f in ${
      lib.concatStringsSep " " [
        "postmarketos/ath10k/WCN3990/hw1.0/bdwlan-flame.bin"
        "postmarketos/ath10k/WCN3990/hw1.0/board-2.bin"
        "postmarketos/ath10k/WCN3990/hw1.0/board-2.json"
        "postmarketos/ath10k/WCN3990/hw1.0/firmware-5.bin"
        "postmarketos/qca/crbtfw01.tlv"
        "qca/crnv01.bin"
        "qcom/a630_gmu.bin"
        "qcom/a630_sqe.fw"
        "qcom/a640_gmu.bin"
        "qcom/sm8150/google/flame/a640_zap.mbn.zst"
        "qcom/sm8150/google/flame/adsp.mbn.zst"
        "qcom/sm8150/google/flame/adspr.jsn"
        "qcom/sm8150/google/flame/adspua.jsn"
        "qcom/sm8150/google/flame/cdsp.mbn.zst"
        "qcom/sm8150/google/flame/cdspr.jsn"
        "qcom/sm8150/google/flame/ipa_fws.mbn.zst"
        "qcom/sm8150/google/flame/modem.mbn.zst"
        "qcom/sm8150/google/flame/modemr.jsn"
        "qcom/sm8150/google/flame/modemuw.jsn"
        "qcom/sm8150/google/flame/slpi.mbn.zst"
        "qcom/sm8150/google/flame/slpir.jsn"
        "qcom/sm8150/google/flame/slpius.jsn"
        "qcom/sm8150/google/flame/venus.mbn.zst"
        "qcom/sm8150/google/flame/wlanmdsp.mbn.zst"
      ]
    }; do
      install -Dm644 lib/firmware/$f $out/lib/firmware/''${f#postmarketos/}
    done
    # the dts asks for the split .mdt names; the kernel loads an .mbn under them
    for n in adsp cdsp modem slpi; do
      ln -s $n.mbn.zst $out/lib/firmware/qcom/sm8150/google/flame/$n.mdt.zst
    done
    ${lib.concatStrings (
      lib.mapAttrsToList (name: src: ''
        install -Dm644 ${src} $out/lib/firmware/${name}
      '') haptics
    )}
    runHook postInstall
  '';

  # some are zstd already
  passthru.compressFirmware = false;

  meta = {
    license = lib.licenses.unfree;
    platforms = [ "aarch64-linux" ];
  };
}
