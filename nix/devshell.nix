{
  perSystem = { self', inputs', config, pkgs, ... }: {
    devshells.default = {
      name = "godot-cardano devshell";
      env = [
        { name = "PRIVATE_TESTNET_PAYMENT_SKEY"; value = builtins.readFile self'.packages.private-testnet-payment-skey; }
        { name = "PRIVATE_TESTNET_PAYMENT_VKEY"; value = builtins.readFile self'.packages.private-testnet-payment-vkey; }
        { name = "PRIVATE_TESTNET_PAYMENT_ADDRESS"; value = builtins.readFile self'.packages.private-testnet-payment-address; }
        { name = "PRIVATE_TESTNET_FUND_ADA_AMOUNT"; value = "1000"; }
      ];
      packages = [
        pkgs.stdenv.cc
      ];
      commands = [
        {
          package = self'.packages.setup-dev-env;
          help = "Set up development environment";
        }
        {
          name = "cardano-cli";
          package = self'.packages.cardano-cli;
        }
        {
          category = "godot";
          package = self'.packages.steam-run;
          help = "Wrapper to run godot exports in an Ubuntu-like environment";
        }
        {
          category = "godot";
          package = self'.packages.godot;
        }
        {
          category = "rust tools";
          package = pkgs.cargo;
        }
        {
          category = "rust tools";
          package = pkgs.rustc;
        }
        {
          category = "rust tools";
          package = pkgs.rust-analyzer;
        }
        {
          category = "public preview testnet";
          package = self'.packages.preview-integration-test;
          help = "Run integration test on public preview testnet";
        }
        {
          category = "private testnet";
          package = pkgs.overmind;
          help = "Use 'overmind start' to start private testnet services: cardano-node, ogmios, kupo";
        }
        {
          category = "private testnet";
          package = self'.packages.private-testnet-integration-test;
          help = "Run integration test on private testnet";
        }
        {
          category = "private testnet";
          name = "local-cluster";
          package = inputs'.plutip.packages."plutip-core:exe:local-cluster";
          help = "Plutip tool for starting local cardano-node cluster";
        }
        {
          category = "private testnet";
          name = "start-cluster";
          package = self'.packages.start-cluster;
          help = "Start local cardano-node cluster in ./local-testnet/ ";
        }
        {
          category = "private testnet";
          name = "start-ogmios";
          package = self'.packages.start-ogmios;
          help = "Start ogmios api bridge for cardano-node";
        }
        {
          category = "private testnet";
          name = "start-kupo";
          package = self'.packages.start-kupo;
          help = "Start kupo chain indexer for cardano-node";
        }
        {
          category = "private testnet";
          package = self'.packages.private-testnet-fund-ada;
          help = "Fund test wallet";
        }
        {
          name = "aiken";
          package = self'.packages.aiken;
        }
      ];
      devshell.startup.setup-dev-env.text = ''
        setup-dev-env
      '';
    };
  };
}
