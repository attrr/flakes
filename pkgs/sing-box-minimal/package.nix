{ prev }:
prev.sing-box.overrideAttrs (old: {
  pname = "sing-box-minimal";
  env = (old.env or { }) // {
    CGO_ENABLED = "0";
  };
  tags = [
    "with_quic"
    "with_utls"
    "badlinkname"
    "tfogo_checklinkname0"
  ];
  ldflags = (old.ldflags or [ ]) ++ [
    "-s"
    "-w"
  ];
})
