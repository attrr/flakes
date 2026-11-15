{ ... }:
{
  isIPv6 = ip: builtins.match ".*:.*" ip != null;
  isIPv4 = ip: builtins.match ".*\\..*" ip != null;
  parseCidr =
    s:
    let
      m = builtins.match "([^/]+)/([0-9]+)" s;
    in
    if m == null then
      throw "helpers.network.parseCidr: invalid CIDR '${s}'"
    else
      {
        address = builtins.elemAt m 0;
        prefixLength = builtins.fromJSON (builtins.elemAt m 1);
      };
}
