{ ... }:
{
  isIPv6 = ip: builtins.match ".*:.*" ip != null;
  isIPv4 = ip: builtins.match ".*\\..*" ip != null;
}
