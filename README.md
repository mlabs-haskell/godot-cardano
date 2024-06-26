# Cardano Game Engine Wallet - Godot Integration

Cardano Game Engine Wallet is an integrated light wallet *and* off-chain SDK for
the Godot engine and Cardano blockchain. The project is currently a *work-in-progress*.

This project was publicly funded by the Cardano community in round 10 of [Project Catalyst](https://projectcatalyst.io/funds/10/f10-developer-ecosystem-the-evolution/mlabs-cardano-game-engine-wallet-godot-integration). Thank you for your support!

## Status

The project currently consists of a small demo that showcases two features:

* Generating / importing a wallet by entering a seed-phrase
* Transferring ADA to an arbitrary Cardano address.

At the momment, the demo runs on the *preview* testnet and was tested on
*Linux and Windows x86-64 PCs*.

## How to build and run the demo with Godot

### Pre-requisites

* Godot Engine 4.2: The demo runs on version 4.2 of the Godot engine, which you
  can download at the [official website](https://godotengine.org/).

* A wallet with funds in the Cardano preview testnet: You can use any wallet you like, as
  long as it supports the preview testnet. *Take note of the seed-phrase of your wallet*. To get test ADA (tADA), use the [Cardano testnet faucet](https://docs.cardano.org/cardano-testnet/tools/faucet/).

* A Blockfrost token: Our demo uses Blockfrost as a provider for querying the blockchain and submitting transactions.
[You will need a Blockfrost account](https://blockfrost.dev/overview/getting-started#log-in--sign-up) and a *preview testnet token*.

### Setup

First, clone the repository and enter the top directory.

```bash
$ git clone https://github.com/mlabs-haskell/godot-cardano.git
$ cd godot-cardano
```

Download `godot-cardano.zip` from the [releases page](https://github.com/mlabs-haskell/godot-cardano/releases/), unzip it and copy the `addons` folder into the `demo` folder of the repo.

```bash
$ curl https://github.com/mlabs-haskell/godot-cardano/releases/download/release-.../godot-cardano.zip -O godot-cardano.zip
$ unzip godot-cardano.zip -o demo
```

Inside the `demo` folder, create a "preview_token.txt" file with your Blockfrost preview token.

```bash
$ echo "<YOUR TOKEN>" > demo/preview_token.txt
```

Open the Godot editor. You will be greeted by the _Project Manager_. Import and open the project located in the `demo` folder.

![Screenshot of the project manager](./screenshots/01_project-manager.png)

![Importing the project](./screenshots/02_import-project.png)

You should now have the Godot editor window with the project loaded. Press the button for running the current scene (or press `F5`).

![Run scene](./screenshots/03_run-scene.png)

### How the demo works

The demo consists of two forms:

1. A form for filling in the wallet's mnemonic phrase
2. A form for transferring ADA to an arbitrary address

*The two forms must be filled in sequence*.

1. First fill in the seed phrase of the wallet specified in the [Pre-requisites section](#pre-requisites).

2. Click on "Set wallet". If the wallet is loaded correctly, the demo should inform you of the amount of UTxOs found in the address
associated to that wallet (as well as the amount of funds in it).

3. Set the recipient address of the transaction (you may use the address of your wallet if you want).

4. Fill in the amount of _lovelace_ to send. A reminder that lovelace is the smallest unit of ADA currency: 1 ADA = 1,000,000 lovelace.
You should send **at least 969,750**. This is the smallest value a UTxO may have in Cardano, any less **will trigger a runtime error**.

5. Click on "Send ADA". This will use the Blockfrost backend to submit the transaction to the Cardano blockchain.

![Forms filled example](./screenshots/filled-forms.png)

At this point the demo is over. The demo will not inform you of the success of the transaction, but you may use any tool to confirm that a transaction occurred between your wallet and the recipient.

For instance, here we use [Cardanoscan (Preview)](https://preview.cardanoscan.io) to monitor the wallet address and confirm that a transaction occurred:

![Cardanoscan check](./screenshots/cardanoscan-check.png)

## What's next?

Check our milestones [here](https://milestones.projectcatalyst.io/projects/1000114)!

You may also read our [Proof Of Achievement / Research report](./docs/M1_PoA-Research-Report.pdf) written for the milestone as well. This document discusses our work and rationale for the technical decisions we have made.

## Development

Development is supported on linux. On other platforms, use a virtual machine or WSL. To get started, clone the repo and enter it.

### Setup

[Install Nix](https://nixos.org/download.html) and [enable flakes](https://nixos.wiki/wiki/Flakes#Installing_flakes), or do it in one step with the [Determinate nix installer](https://github.com/DeterminateSystems/nix-installer).

### Build Asset

```bash
$ nix build .#godot-cardano
```

#### Build and Run Demo

```bash
$ nix build .#demo
$ nix run .#steam-run result/bin/demo
```

### Run Integration Test on preview network

Before running the tests, ensure that `test/preview_token.txt` is populated
with a valid Blockfrost preview key, and that `test/seed_phrase.txt` is
populated with a valid 24-word seed phrase and the address is funded with
testnet ADA from the faucet. Alternatively, your seed phrase can be set via the
`TESTNET_SEED_PHRASE` environment variable. The address used will be the
default address in most light wallets, as well as in the demo app provided with
this project. Once these are set, run the test suite:

Run integration test on preview network.

```bash
$ nix run .#preview-integration-test
```

### Development shell

Enter development shell with all dependencies in PATH and addons linked. A list of useful commands is displayed.

```bash
$ nix develop
🔨 Welcome to godot-cardano devshell

[[general commands]]

  cardano-cli - The Cardano command-line interface

...
```

Here are some useful workflows inside the development shell:

#### Build the Godot extension

```bash
$ cd libcsl_godot
$ cargo build
$ ls target/debug/libcsl_godot.so
$ ls -la ../addons/@mlabs-haskell/godot-cardano/bin/
```

#### Open the demo app in Godot editor

```bash
$ cd demo
$ echo "<your bockfrost preview token>" > preview_token.txt
$ godot4 --editor
```

With the `demo` or `test` project open, the Godot editor should automatically reload the gdextension after `cargo build`.

#### Export and run the demo

```bash
$ cd demo
$ godot4 --headless --export-debug  "Linux/X11" out/demo project.godot
$ steam-run out/demo
```

#### Run integration tests on preview network

```bash
$ cd test
$ godot4 --headless --script addons/gut/gut_cmdln.gd
```

#### Start private testnet and fund wallet

```bash
$ overmind start -D
$ private-testnet-fund-ada
$ echo $PRIVATE_TESTNET_PAYMENT_ADDRESS
$ echo $PRIVATE_TESTNET_PAYMENT_VKEY
$ echo $PRIVATE_TESTNET_PAYMENT_SKEY
$ overmind quit
```
