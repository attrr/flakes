# stage0 — tiny busybox cpio that loop-mounts the stage1 initrd (repacked
# as squashfs) and switch_roots into it, keeping the toolset compressed in RAM.
#
# system.build.rescue:
#   bzImage          kernel
#   initrd           merged (stage0 + squashfs in one cpio)
#   stage0.initrd    stage0 only, squashfs found via root=/stage1.path= or disk scan
#   stage1.squashfs  repacked stage1 initrd
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stage0;

  dirs = pkgs.runCommand "stage0-dirs" { } ''
    mkdir -p $out/{proc,sys,dev,mnt/ro,mnt/rw,mnt/root,mnt/part}
  '';

  init = pkgs.runCommand "stage0-init" {
    src = pkgs.replaceVars ./init.sh {
      HARDWARE_MODULES = lib.concatStringsSep " " cfg.kernelModules;
    };
  } "install -m755 $src $out";

  squashfs =
    pkgs.runCommand "stage1.squashfs"
      {
        nativeBuildInputs = with pkgs; [
          squashfsTools
          cpio
          zstd
        ];
      }
      ''
        mkdir unpack && cd unpack
        zstd -d < ${cfg.stage1Initrd}/initrd | cpio -idm --no-preserve-owner 2>/dev/null
        cd ..
        mksquashfs unpack $out \
          -comp ${cfg.squashfsCompression} \
          -no-xattrs -all-root -b 1048576 \
          -processors $NIX_BUILD_CORES
      '';

  squashfsCpio = pkgs.runCommand "stage1.squashfs.cpio" { nativeBuildInputs = [ pkgs.cpio ]; } ''
    mkdir root && cp ${squashfs} root/stage1.squashfs
    cd root && find . -mindepth 1 -printf "%P\n" | cpio -o -H newc -R 0:0 > $out
  '';

  contents = [
    {
      source = init;
      target = "/init";
    }
    {
      source = "${pkgs.pkgsStatic.busybox}/bin/busybox";
      target = "/bin/busybox";
    }
    {
      source = "${config.system.build.modulesClosure}/lib";
      target = "/lib";
    }
  ]
  ++ lib.forEach [ "proc" "sys" "dev" "mnt" ] (d: {
    source = "${dirs}/${d}";
    target = "/${d}";
  });

  mkInitrd =
    extra:
    pkgs.makeInitrdNG (
      {
        inherit (config.boot.initrd) compressor compressorArgs;
        inherit contents;
      }
      // extra
    );
in
{
  options.stage0 = {
    stage1Initrd = lib.mkOption {
      type = lib.types.path;
      description = "initrd to repack as squashfs";
    };
    squashfsCompression = lib.mkOption {
      type = lib.types.str;
      default = "zstd -Xcompression-level 19";
    };
    kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "modules probed by stage0 before looking for the squashfs";
    };
  };

  config = {
    boot.initrd.availableKernelModules = [
      "loop"
      "squashfs"
      "overlay"
    ]
    ++ cfg.kernelModules;

    system.build.rescue = pkgs.runCommand "rescue" { } ''
      mkdir $out
      ln -s ${config.system.build.kernel}/${config.system.boot.loader.kernelFile} $out/bzImage
      ln -s ${mkInitrd { prepend = [ squashfsCpio ]; }}/initrd $out/initrd
      ln -s ${mkInitrd { }}/initrd $out/stage0.initrd
      ln -s ${squashfs} $out/stage1.squashfs
    '';
  };
}
