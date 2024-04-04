{ withSystem, ... }: {
  perSystem = { self', inputs', pkgs, ... }:
    let
      ogmiosBin = "${inputs'.cardano-nix.packages.ogmios}/bin/ogmios";
      kupoBin = inputs'.kupo-nixos.packages.kupo.exePath;
      cardanoCliBin = inputs'.cardano-nix.packages.cardano-cli.exePath;
      scriptCommon = ''
        set -euo pipefail
        sleep 1;

        echo -e "Waiting for cluster info ..";
        cluster_info="local-cluster-info.json";
        while [ ! -f $cluster_info ]; do sleep 1; done;

        echo -e "Waiting for socket ..";
        while
          socket=$(${pkgs.jq}/bin/jq .ciNodeSocket $cluster_info --raw-output)
          sleep 1
          [ ! -S $socket ]
        do true; done
        echo "Socket found: " $socket "       "

        config=''${socket/node.socket/node.config}

        OGMIOS_PORT=''${OGMIOS_PORT:-9001}
        KUPO_PORT=''${KUPO_PORT:-9002}
      '';
      startKupo = pkgs.writeShellScript "startKupo" ''
        ${scriptCommon}

        ${kupoBin} \
          --node-socket $socket \
          --node-config $config \
          --match '*' \
          --match '*/*' \
          --since origin \
          --in-memory \
          --host 127.0.0.1 \
          --port $KUPO_PORT
      '';
      startOgmios = pkgs.writeShellScript "startOgmios" ''
        ${scriptCommon}

        ${ogmiosBin} \
          --node-socket $socket \
          --node-config $config \
          --host 127.0.0.1 \
          --port $OGMIOS_PORT
      '';
      startPlutip = pkgs.writeShellScript "startPlutip" ''
        ${inputs'.plutip.apps."plutip-core:exe:local-cluster".program} --wallet-dir wallets
      '';
      fundAda = pkgs.writeShellScript "fundAda" ''
        ${scriptCommon}

        export CARDANO_NODE_SOCKET_PATH=$socket

        mkdir -p ./txns

        if [ -z ''${ADDRESS_TO_FUND+x} ]; then
          echo "Please set ADDRESS_TO_FUND environment variable"
          exit -1;
        fi;

        if [ -z ''${FUND_ADA+x} ]; then
          echo "Please set FUND_ADA environment variable"
          exit -1;
        fi;

        while [ ! -d wallets ]; do sleep 1; done

        do=true;
        while $do || [ ! -f $vkey ]; do
          do=false;
          vkey="wallets/$(ls wallets | grep verification)"
          sleep 1;
        done;

        address=$( \
          ${cardanoCliBin} latest \
          address \
          build \
          --payment-verification-key-file \
          $vkey \
          --mainnet \
        )

        echo
        echo Source Address: $address

        txn=$( \
          ${cardanoCliBin} \
            query \
            utxo \
            --address $address \
            --mainnet \
          | head -n 3 | tail -n 1 \
        )

        txHash=$(echo $txn | cut -d' ' -f 1)
        txIdx=$(echo $txn | cut -d' ' -f 2)

        echo Source UTxO: "$txHash#$txIdx"

        fundAddress=$ADDRESS_TO_FUND
        fundLovelace=$(echo "$FUND_ADA*1000000"|bc)

        echo && echo "Sending $FUND_ADA ADA to $ADDRESS_TO_FUND" && echo

        ${cardanoCliBin} \
          latest \
          transaction \
          build \
          --mainnet \
          --tx-in "$txHash#$txIdx" \
          --tx-out $fundAddress+$fundLovelace \
          --change-address $address \
          --out-file ./txns/txn-fund-ada.json;

        ${cardanoCliBin} \
          latest \
          transaction \
          sign \
          --tx-file ./txns/txn-fund-ada.json \
          --signing-key-file ./wallets/signing-key*.skey \
          --mainnet \
          --out-file ./txns/txn-fund-ada-signed.json;

        ${cardanoCliBin} \
          latest \
          transaction \
          submit \
          --tx-file txns/txn-fund-ada-signed.json \
          --mainnet;

        touch .ready
      '';
      test = pkgs.writeShellScript "test" ''
        set -e
        ${fundAda}
        while [ ! -f .ready ]; do sleep 1; done;
        echo "Reimporting resources..."
        timeout 10s ${self'.packages.godot}/bin/godot4 --headless --editor || true
        echo "Running tests..."
        # TODO: set up wallet and run test
        # ${self'.packages.test}/bin/godot-cardano-test
        echo "Mock tests."
        echo "Success. Exiting."
        ${pkgs.overmind}/bin/overmind quit
        sleep 10
      '';
      procfile = pkgs.writeText "Procfile" ''
        plutip: ${startPlutip}
        ogmios: ${startOgmios}
        kupo: ${startKupo}
        test: ${test}
      '';
      payment_vkey = pkgs.writeText "vkey" ''
        {
            "type": "PaymentVerificationKeyShelley_ed25519",
            "description": "Payment Verification Key",
            "cborHex": "582000612bbacfc5b2b640ca70dd39f9925f5c14785dd7169eab6574849794a06d02"
        }
      '';
      payment_skey = pkgs.writeText "skey" ''
        {
            "type": "PaymentSigningKeyShelley_ed25519",
            "description": "Payment Signing Key",
            "cborHex": "5820a9c5fabbf73872da42cc728b4ea47df1d03a94f154cca7edda57d6715bedb363"
        }
      '';
      # Do not send anything to this address on mainnet. It is used on a private testnet and the keys are above.
      payment_address = "addr1v9d0353jyxa6sneu48ty6284att78mc3knt0k3ctk23scpccjg8yu";
    in
    {
      packages.plutip-test = pkgs.writeShellScriptBin "plutip-test" ''
        TMP=$(${pkgs.mktemp}/bin/mktemp -d)
        cp -r ./test $TMP/test
        cp -r ./addons $TMP/addons
        cd $TMP
        chmod -R u+rw ./test ./addons
        export PAYMENT_VKEY='${payment_vkey}'
        export PAYMENT_SKEY='${payment_skey}'
        export ADDRESS_TO_FUND=${payment_address}
        export FUND_ADA=1000
        cp ${procfile} ./Procfile
        ${pkgs.overmind}/bin/overmind start
        echo Overmind exited.
      '';
      # TODO: fix test running in sandbox
      # checks.plutip-test = pkgs.runCommand "plutip-test" {} ''
      #   ${self'.packages.plutip-test}/bin/plutip-test
      #   mkdir $out
      # '';
    };
  flake.effects = _: withSystem "x86_64-linux" (
    { config, hci-effects, pkgs, inputs', ... }:
    {
      plutip-test = hci-effects.mkEffect {
        effectScript = ''
          ${config.packages.plutip-test}/bin/plutip-test
        '';
      };
    }
  );
}
