extends RefCounted
class_name JsCip30Api

## Class responsible for initilizing the global Cardano object in a web environment
##
## This class is used internally by [Cip30Callbacks]. If you want to use the wallet
## provided by godot-cardano in a web environment, check the documentation for that
## class instead.[br][br]
##
## You should only use this class if you know what you are doing.

## Initialize `window.cardano` (if it does not exist yet) and register the
## godot-cardano wallet.
func init_cip_30_api():
	JavaScriptBridge.eval("""
	function initCip30Godot() {
			if (!window.cardano) {
				window.cardano = new Object();
			}
			window.cardano.godot = cip30Godot;
			console.log('GD:JS eval: done setting CIP-30 Godot wallet to `window.cardano.godot`');
		}

	const cip30Godot = {
			name: "godot",
			icon: null,
			enable: enableGodotCardano,
			callbacks: new Object()
		}

	async function enableGodotCardano() {
			return cip30ApiGodot
		}

	const cip30ApiGodot = {
			name: "godot",
			getUsedAddresses: () => wrapCb(window.cardano.godot.callbacks.get_used_addresses),
			getUnusedAddresses: () => wrapCb(window.cardano.godot.callbacks.get_unused_addresses),
			signData: (address, message) => wrapSignCb(
				window.cardano.godot.callbacks.sign_data,
				address,
				message
			),
		}

	function wrapCb(cb) {
			let { promise, resolve, reject } = Promise.withResolvers();
			cb(resolve);
			return promise;
		}

	function wrapSignCb(cb, address, message) {
			let { promise, resolve, reject } = Promise.withResolvers();
			cb(resolve, reject, address, message);
			return promise;
		}
	
	initCip30Godot();
		
	""")
