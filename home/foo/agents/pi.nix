{ pkgsUnstable, ... }:
let
  models = {
    providers.openrouter.compat.openRouterRouting = {
      only = [
        # official providers
        "openai"
        "azure"
        "anthropic"
        "amazon-bedrock"
        "claude-on-aws"
        "google-vertex"
        "google-ai-studio"
        "xai"

        # major providers
        "meta"
        "deepinfra"
        "together"
        "fireworks"
        "nebius"
        "coreweave"
        "cloudflare"
        "baseten"
        "parasail"
        "groq"
        "cerebras"
        "sambanova"
        "nvidia"
        "inference-net"

        # low-cost / experimental (429 / quantization risk)
        "particle-ai"
        "wafer"
        "primeintellect"
        "sail-research"
        "ionstream"
        "morph"
        "relace"
        "digitalocean"
        "cohere"
        "venice"
      ];
      sort = "price";
      require_parameters = true;
      allow_fallbacks = true;
    };
  };
in
{
  home.packages = [ pkgsUnstable.pi-coding-agent ];

  home.file.".pi/agent/models.json".text = builtins.toJSON models;
}
