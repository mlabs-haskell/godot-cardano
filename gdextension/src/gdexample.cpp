#include "gdexample.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void GDExample::_bind_methods() {
  ClassDB::bind_method(D_METHOD("set_address"), &GDExample::set_address);
}

GDExample::GDExample() {
  time_passed = 0.0;
  address = NULL;
}

GDExample::~GDExample() {
  if (address != NULL)
    free_address(address);
}

void GDExample::_process(double delta) {
  time_passed += delta;

  Vector2 new_position = Vector2(10.0 + (10.0 * sin(time_passed * 2.0)), 10.0 + (10.0 * cos(time_passed * 1.5)));

  set_position(new_position);
}

void GDExample::set_address(String addr_bech32) {
  if (address != NULL)
    free_address(address);
  const char *c_string = addr_bech32.ascii().get_data();
  address = new_address_from_bech32(c_string);
  const char *address_hex = address_to_hex(address);
  UtilityFunctions::print(address_hex);
  free_string(address_hex);
}
