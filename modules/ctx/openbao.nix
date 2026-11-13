{
  lib,
  ctx,
  ...
}:
let
  bao = ctx.services.openbao or { enable = false; };
in
lib.mkIf bao.enable {
  sops.secrets."${bao.unseal-key.name}".owner = "openbao";

  infra.openbao = {
    enable = true;
    domain = lib.mkDefault bao.domain;
    unsealKeyFile = lib.mkDefault bao.unseal-key.path;
    listenAddresses = lib.mkDefault ctx.tailscale.ips;
  };
}
