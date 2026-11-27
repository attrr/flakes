# Multi-class feature resolver (`includes`, `module`, `ctx`, or shorthand `common`/`<class>`).
# Plain modules pass through unchanged; path-sourced slots get `key` + `_file` for deduplication.
{ lib }:
let
  classKeys = [
    "common"
    "os"
    "nixos"
    "finix"
    "homeManager"
  ];
  osClasses = [
    "nixos"
    "finix"
  ];
  featureKeys = classKeys ++ [
    "includes"
    "module"
    "ctx"
  ];

  hasAny = keys: v: builtins.isAttrs v && builtins.any (k: v ? ${k}) keys;
  asList = x: if builtins.isList x then x else [ x ];

  tagSlot =
    raw: tag: mods:
    if builtins.isPath raw then
      [
        {
          key = "${toString raw}#${tag}";
          _file = raw;
          imports = mods;
        }
      ]
    else
      mods;

  extractClassMap =
    raw: prefix: class: m:
    (if m ? common then tagSlot raw "${prefix}:common" (asList m.common) else [ ])
    ++ (
      if m ? os && builtins.elem class osClasses then tagSlot raw "${prefix}:os" (asList m.os) else [ ]
    )
    ++ (
      if m ? os && builtins.elem class osClasses then tagSlot raw "${prefix}:os" (asList m.os) else [ ]
    )
    ++ (if m ? ${class} then tagSlot raw "${prefix}:${class}" (asList m.${class}) else [ ]);

  extractSection =
    raw: prefix: class: sec:
    if hasAny classKeys sec then
      extractClassMap raw prefix class sec
    else
      tagSlot raw prefix (asList sec);

  resolveOne =
    includeCtx: class: raw:
    let
      v = if builtins.isPath raw then import raw else raw;
    in
    if hasAny featureKeys v then
      lib.concatMap (resolveOne includeCtx class) (v.includes or [ ])
      ++ (
        if v ? module then
          extractSection raw "module" class v.module
        else
          extractClassMap raw "module" class v
      )
      ++ lib.optionals (includeCtx && v ? ctx) (extractSection raw "ctx" class v.ctx)
    else
      [ raw ];
in
{
  resolve = class: items: lib.concatMap (resolveOne true class) items;
  resolveModule = class: items: lib.concatMap (resolveOne false class) items;
  asModule = class: item: { imports = lib.concatMap (resolveOne true class) (asList item); };
}
