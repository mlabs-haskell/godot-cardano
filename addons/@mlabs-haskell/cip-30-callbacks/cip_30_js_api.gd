extends RefCounted

class_name JsCip30Api

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
