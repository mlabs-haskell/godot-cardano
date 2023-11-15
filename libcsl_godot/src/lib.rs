use cardano_serialization_lib::address::Address;
use godot::prelude::*;
use godot::engine::Sprite2D;
use godot::engine::ISprite2D;

struct MyExtension;

#[derive(GodotClass)]
#[class(base=Sprite2D)]
struct Player {
    address: Option<Address>,

    angular_speed: f64,

    #[base]
    sprite: Base<Sprite2D>
}

#[godot_api]
impl ISprite2D for Player {
    fn init(sprite: Base<Sprite2D>) -> Self {
        Self {
            angular_speed: std::f64::consts::PI,
            sprite,
            address: None
        }
    }

    fn physics_process(&mut self, delta: f64) {
        self.sprite.rotate((self.angular_speed * delta) as f32);
    }
}
    
#[godot_api]
impl Player {
    #[func]
    fn set_address(&mut self, addr_bech32: String) {
        self.address = Some(Address::from_bech32(&addr_bech32).expect("Could not parse address bech32"));
        godot_print!("Parsed address, got hex: {}", self.address.as_ref().expect("Unexpected address error").to_hex());
    }
}

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}
