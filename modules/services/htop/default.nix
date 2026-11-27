{ config, lib, ... }:
let
  cfg = config.programs.htop;
in
{
  options.programs.htop.cpuColumns = lib.mkOption {
    type = lib.types.enum [
      1
      2
      4
    ];
    default = 1;
    description = "Number of columns for the AllCPUs meter.";
  };

  config = lib.mkIf cfg.enable {
    programs.htop.settings = lib.mapAttrs (_: lib.mkDefault) rec {
      # fundamental
      highlight_base_name = true;
      tree_view = true;
      show_cpu_frequency = true;

      # less verbose
      show_program_path = false;
      hide_kernel_threads = true;
      hide_userland_threads = true;

      # steal time
      detailed_cpu_time = true;

      # panel
      left_meters = [
        (if cfg.cpuColumns == 1 then "AllCPUs" else "AllCPUs${toString cfg.cpuColumns}")
        "Memory"
        "Swap"
      ];
      left_meter_modes = lib.replicate (builtins.length left_meters) 1;
      right_meters = [
        "NetworkIO"
        "DiskIO"
        "Tasks"
        "LoadAverage"
        "Uptime"
        "CPU"
      ];
      right_meter_modes = lib.replicate (builtins.length right_meters) 2;
    };
  };
}
