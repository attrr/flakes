# desktop login, ssh and wg0 from ctx
{
  lib,
  config,
  ctx,
  ...
}:
let
  wg = ctx.services.wireguard;
  hub = builtins.head wg.peers;
in
{
  networking.hostName = ctx.metadata.hostname;

  assertions = [
    {
      assertion = config.users.users.foo.hashedPassword != null;
      message = "${ctx.metadata.hostname}: set ssh.hashed-password in ctx";
    }
  ];
  users.users.foo.hashedPassword = ctx.ssh.hashed-password;

  services.openssh = {
    enable = true;
    ports = ctx.ssh.ports;
    users.foo.authorizedKeys = ctx.ssh.auth-keys;
    lockRootLogin = true;
  };

  networking.nameservers = map (addr: builtins.head (lib.splitString "/" addr)) hub.addresses;
  networking.wireguard.interfaces.wg0 = {
    ips = wg.addresses;
    listenPort = 51820;
    privateKeyFile = wg.private-key.path;
    peers = [
      {
        publicKey = hub.public-key;
        presharedKeyFile = wg.pre-shared-key.path;
        allowedIPs = [
          "0.0.0.0/0"
          "::/0"
        ];
        endpoint = hub.endpoint;
      }
    ];
  };
}
