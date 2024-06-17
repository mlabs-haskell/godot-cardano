{ self, withSystem, ... }: {
  perSystem = { self', inputs', config, pkgs, ... }:
    let
      wait-for-socket = ''
        set -e
        set -o pipefail
        echo -e "Waiting for cluster info ..";
        cluster_info="local-cluster-info.json";
        while [ ! -f $cluster_info ]; do sleep 1; done;

        echo -e "Waiting for socket ..";
        while
          CARDANO_NODE_SOCKET_PATH=$(${pkgs.jq}/bin/jq .ciNodeSocket $cluster_info --raw-output)
          sleep 1
          [ ! -S $CARDANO_NODE_SOCKET_PATH ]
        do true; done
        echo "Socket found: " $CARDANO_NODE_SOCKET_PATH
        CARDANO_NODE_CONFIG_PATH=''${CARDANO_NODE_SOCKET_PATH/node.socket/node.config}
      '';
    in
    {
      packages = {
        private-testnet-fund-ada = pkgs.writeShellScriptBin "private-testnet-fund-ada" ''
          ${wait-for-socket}
          mkdir -p ./private-testnet/txns

          if [ -z ''${PRIVATE_TESTNET_PAYMENT_ADDRESS+x} ]; then
            echo "Please set PRIVATE_TESTNET_PAYMENT_ADDRESS environment variable"
            exit -1;
          fi;

          if [ -z ''${PRIVATE_TESTNET_FUND_ADA_AMOUNT+x} ]; then
            echo "Please set PRIVATE_TESTNET_FUND_ADA_AMOUNT environment variable"
            exit -1;
          fi;

          while [ ! -d private-testnet/wallets ]; do sleep 1; done

          do=true;
          while $do || [ ! -f $vkey ]; do
            do=false;
            vkey="private-testnet/wallets/$(ls private-testnet/wallets | grep verification)"
            sleep 1;
          done;

          address=$( \
            ${self'.packages.cardano-cli.exePath} latest address build \
            --payment-verification-key-file $vkey \
            --mainnet \
          )

          echo; echo Source Address: $address

          ${self'.packages.cardano-cli.exePath} \
              query utxo \
              --socket-path $CARDANO_NODE_SOCKET_PATH \
              --address $address \
              --mainnet

          txn=$( \
            ${self'.packages.cardano-cli.exePath} \
              query utxo \
              --socket-path $CARDANO_NODE_SOCKET_PATH \
              --address $address \
              --mainnet \
            | head -n 3 | tail -n 1 \
          )
          echo $txn

          txHash=$(echo $txn | cut -d' ' -f 1)
          txIdx=$(echo $txn | cut -d' ' -f 2)

          echo Source UTxO: "$txHash#$txIdx"

          fundAddress=''${1-''${PRIVATE_TESTNET_PAYMENT_ADDRESS?"No wallet address provided for funding"}}
          fundLovelace=$(echo "$PRIVATE_TESTNET_FUND_ADA_AMOUNT*1000000"|${pkgs.bc}/bin/bc)

          echo && echo "Sending $PRIVATE_TESTNET_FUND_ADA_AMOUNT ADA to $fundAddress" && echo

          ${self'.packages.cardano-cli.exePath} \
            latest transaction build \
            --socket-path $CARDANO_NODE_SOCKET_PATH \
            --mainnet \
            --tx-in "$txHash#$txIdx" \
            --tx-out $fundAddress+$fundLovelace \
            --change-address $address \
            --out-file ./private-testnet/txns/txn-fund-ada.json;

          ${self'.packages.cardano-cli.exePath} \
            latest transaction sign \
            --tx-file ./private-testnet/txns/txn-fund-ada.json \
            --signing-key-file ./private-testnet/wallets/signing-key*.skey \
            --mainnet \
            --out-file ./private-testnet/txns/txn-fund-ada-signed.json;

          ${self'.packages.cardano-cli.exePath} \
            latest transaction submit \
            --socket-path $CARDANO_NODE_SOCKET_PATH \
            --tx-file ./private-testnet/txns/txn-fund-ada-signed.json \
            --mainnet;

          touch .ready
        '';
        start-cluster = pkgs.writeShellScriptBin "start-cluster" ''
          set -e
          mkdir -p private-testnet
          ${inputs'.plutip.apps."plutip-core:exe:local-cluster".program} \
            --wallet-dir private-testnet/wallets \
            --working-dir private-testnet/plutip
        '';
        start-ogmios = pkgs.writeShellScriptBin "start-ogmios" ''
          ${wait-for-socket}
          OGMIOS_PORT=''${OGMIOS_PORT:-9001}
          ${inputs'.cardano-nix.packages.ogmios}/bin/ogmios \
            --node-socket $CARDANO_NODE_SOCKET_PATH \
            --node-config $CARDANO_NODE_CONFIG_PATH \
            --host 127.0.0.1 \
            --port $OGMIOS_PORT
        '';
        start-kupo = pkgs.writeShellScriptBin "start-kupo" ''
          ${wait-for-socket}
          KUPO_PORT=''${KUPO_PORT:-9002}
          ${inputs'.kupo-nixos.packages.kupo.exePath} \
            --node-socket $CARDANO_NODE_SOCKET_PATH \
            --node-config $CARDANO_NODE_CONFIG_PATH \
            --match '*' \
            --match '*/*' \
            --since origin \
            --in-memory \
            --host 127.0.0.1 \
            --port $KUPO_PORT
        '';
        private-testnet-payment-vkey = pkgs.writeText "vkey" ''
          {
              "type": "PaymentVerificationKeyShelley_ed25519",
              "description": "Payment Verification Key",
              "cborHex": "582000612bbacfc5b2b640ca70dd39f9925f5c14785dd7169eab6574849794a06d02"
          }
        '';
        private-testnet-payment-skey = pkgs.writeText "skey" ''
          {
              "type": "PaymentSigningKeyShelley_ed25519",
              "description": "Payment Signing Key",
              "cborHex": "5820a9c5fabbf73872da42cc728b4ea47df1d03a94f154cca7edda57d6715bedb363"
          }
        '';
        # Do not send anything to this address on mainnet. It is used on a private testnet and the keys are above.
        private-testnet-payment-address = pkgs.writeText "address" "addr1v9d0353jyxa6sneu48ty6284att78mc3knt0k3ctk23scpccjg8yu";
        private-testnet-test = pkgs.writeShellScriptBin "private-testnet-test" ''
          ${wait-for-socket}
          ${self'.packages.private-testnet-fund-ada}/bin/private-testnet-fund-ada
          while [ ! -f .ready ]; do sleep 1; done;

          echo "Running tests..."
          # TODO: set up wallet and run test
          echo "Mock tests."
          # # uncomment to simulate failure
          # exit 1

          touch success
          echo Test script succeeded.
        '';
        private-testnet-integration-test = pkgs.writeShellScriptBin "private-testnet-integration-test" ''
          set -e
          TMP=$(${pkgs.mktemp}/bin/mktemp -d)
          cp -r ./test $TMP/test
          cp -r ./addons $TMP/addons
          cd $TMP
          chmod -R u+rw ./test ./addons
          export PAYMENT_VKEY='${self'.packages.private-testnet-payment-vkey}'
          export PAYMENT_SKEY='${self'.packages.private-testnet-payment-skey}'
          export PRIVATE_TESTNET_PAYMENT_ADDRESS=$(cat ${self'.packages.private-testnet-payment-address})
          export PRIVATE_TESTNET_FUND_ADA_AMOUNT=1000

          ${pkgs.parallel}/bin/parallel --will-cite \
            -j0 --lb --halt now,done=1 ::: \
            ${self'.packages.start-cluster}/bin/start-cluster \
            ${self'.packages.start-ogmios}/bin/start-ogmios \
            ${self'.packages.start-kupo}/bin/start-kupo \
            ${self'.packages.private-testnet-test}/bin/private-testnet-test
          RESULT=$?
          [ ! "0" -eq "$RESULT" ] && echo "Integration test failed." && exit 1
          [ ! -f success ] && echo "Integration test failed." && exit 1
          echo  "Integration test succeeded."
        '';
      };
      checks.private-testnet-integration-test = pkgs.runCommand "private-testnet-integration-check" { } ''
        cd ${self}
        ${self'.packages.private-testnet-integration-test}/bin/private-testnet-integration-test
        touch $out
      '';
    };
}
