{ prev }:
prev.usque.overrideAttrs (old: {
  pname = "usque-static";
  env = (old.env or { }) // {
    CGO_ENABLED = "0";
  };
  ldflags = (old.ldflags or [ ]) ++ [
    "-s"
    "-w"
  ];
})
