{ lib, fetchgit, fetchzip }:

lib.makeOverridable (
{ owner, repo, rev
, name ? null # Override with null to use the default value
, pname ? "source-${githubBase}-${owner}-${repo}"
, fetchSubmodules ? false, leaveDotGit ? null
, deepClone ? false, private ? false, forceFetchGit ? false
, sparseCheckout ? []
, githubBase ? "github.com", varPrefix ? null
, passthru ? { }
, meta ? { }
, ... # For hash agility
}@args:

let
  name = if args.name or null != null then args.name
  else "${pname}-${rev}";

  position = (if args.meta.description or null != null
    then builtins.unsafeGetAttrPos "description" args.meta
    else builtins.unsafeGetAttrPos "rev" args
  );
  baseUrl = "https://${githubBase}/${owner}/${repo}";
  newPassthru = passthru // {
    inherit rev owner repo;
  };
  newMeta = meta // {
    homepage = meta.homepage or baseUrl;
  } // lib.optionalAttrs (position != null) {
    # to indicate where derivation originates, similar to make-derivation.nix's mkDerivation
    position = "${position.file}:${toString position.line}";
  };
  passthruAttrs = removeAttrs args [ "owner" "repo" "rev" "fetchSubmodules" "forceFetchGit" "private" "githubBase" "varPrefix" ];
  varBase = "NIX${lib.optionalString (varPrefix != null) "_${varPrefix}"}_GITHUB_PRIVATE_";
  useFetchGit = fetchSubmodules || (leaveDotGit == true) || deepClone || forceFetchGit || (sparseCheckout != []);
  # We prefer fetchzip in cases we don't need submodules as the hash
  # is more stable in that case.
  fetcher =
    if useFetchGit then fetchgit
    # fetchzip may not be overridable when using external tools, for example nix-prefetch
    else if fetchzip ? override then fetchzip.override { withUnzip = false; }
    else fetchzip;
  privateAttrs = lib.optionalAttrs private {
    netrcPhase = ''
      if [ -z "''$${varBase}USERNAME" -o -z "''$${varBase}PASSWORD" ]; then
        echo "Error: Private fetchFromGitHub requires the nix building process (nix-daemon in multi user mode) to have the ${varBase}USERNAME and ${varBase}PASSWORD env vars set." >&2
        exit 1
      fi
      cat > netrc <<EOF
      machine ${githubBase}
              login ''$${varBase}USERNAME
              password ''$${varBase}PASSWORD
      EOF
    '';
    netrcImpureEnvVars = [ "${varBase}USERNAME" "${varBase}PASSWORD" ];
  };

  gitRepoUrl = "${baseUrl}.git";

  fetcherArgs = (if useFetchGit
    then {
      inherit rev deepClone fetchSubmodules sparseCheckout; url = gitRepoUrl;
      passthru = newPassthru;
    } // lib.optionalAttrs (leaveDotGit != null) { inherit leaveDotGit; }
    else {
      url = "${baseUrl}/archive/${rev}.tar.gz";

      passthru = newPassthru // {
        inherit gitRepoUrl;
      };
    }
  ) // privateAttrs // passthruAttrs // { inherit name; };
in

(fetcher fetcherArgs).overrideAttrs (finalAttrs: previousAttrs: {
  meta = newMeta;
})
)
