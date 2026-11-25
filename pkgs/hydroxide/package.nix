{
  prev,
  fetchFromCodeberg,
}:

prev.hydroxide.overrideAttrs (_: rec {
  version = "0.2.33";

  src = fetchFromCodeberg {
    owner = "emersion";
    repo = "hydroxide";
    rev = "v${version}";
    hash = "sha256-HwnF2Q1380GldXAKMupfqC8y+rlW109cy9dQPJBFPGc=";
  };

  vendorHash = "sha256-wLkdLcaXuE/LdoF6V2STB1Mv4nfmgIwXVH7bmOvUWNY=";
})
