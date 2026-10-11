{
  lib,
  runCommand,
  writeText,
  nixdoc,
  jq,
  pandoc,
}:
let
  source = lib.fileset.toSource {
    root = ../.;
    fileset = ../lib;
  };
  functions = {
    mkPackages = "mk-packages";
    mkPackage = "mk-package";
    mkPublication = "mk-publication";
    mkPayload = "mk-payload";
    mkSnapshots = "mk-snapshots";
    mkPublic = "mk-public";
    mkApt = "mk-apt";
    mkDnf = "mk-dnf";
    mkPacman = "mk-pacman";
    internal.mkRepository = "mk-repository";
    internal.hooks = "hooks";
    internal.packageIntegrations = "package-integrations";
  };
  fileSources =
    prefix: entries:
    lib.mapAttrsToList (name: file: {
      path = "${prefix}.${name}";
      file = "lib/${file}.nix";
      mode = "file";
    }) entries;
  manifest = writeText "nixdoc-manifest.json" (
    builtins.toJSON {
      version = 1;
      sources = [
        {
          path = "metarepo";
          file = "lib/default.nix";
          include = [ "forPkgs" ];
        }
      ]
      ++ fileSources "metarepo" (builtins.removeAttrs functions [ "internal" ])
      ++ fileSources "metarepo.internal" functions.internal;
    }
  );
in
runCommand "metarepo-doc"
  {
    nativeBuildInputs = [
      nixdoc
      jq
      pandoc
    ];
  }
  ''
    mkdir -p "$out"
    nixdoc --manifest ${manifest} --root ${source} --output "$out/api.json"
    jq -er '
      if (.entries | length) != 13 then error("Missing library doc-comments") else
      ["# Metarepo library reference",
       "Generated from Nix doc-comments with nixdoc. See the [library guide](library.html) and [installation guide](install.html). Entries under metarepo.internal describe implementation helpers.",
       (.entries[] | "## `" + .attrPath + "`\n\n" +
         (.description | gsub("(?m)^# (?<section>Type|Inputs|Examples)$"; "### \(.section)")))]
      | join("\n\n")
      end
    ' "$out/api.json" > "$out/api.md"
    sed 's|../public/doc/api.md|index.html|g; s|review.md|review.html|g' \
      ${./library.md} > "$out/library.md"
    cp ${./install.md} "$out/install.md"
    cp ${./review.md} "$out/review.md"
    cp ${./style.css} "$out/style.css"
    for page in api library install review; do
      target=$page
      language=en
      if [ "$page" = api ]; then target=index; fi
      if [ "$page" = review ]; then language=es; fi
      pandoc "$out/$page.md" --from markdown --to html5 --standalone --toc --toc-depth=2 \
        --no-highlight --template ${./template.html} \
        --metadata title="Metarepo: $page" --metadata lang="$language" \
        --output "$out/$target.html"
    done
  ''
