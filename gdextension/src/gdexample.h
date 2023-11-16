#ifndef GDEXAMPLE_H
#define GDEXAMPLE_H

#include <godot_cpp/classes/sprite2d.hpp>

#include "libcsl.h"

namespace godot {
  class GDExample : public Sprite2D {
    GDCLASS(GDExample, Sprite2D)

    private:
      double time_passed;
      const Address *address;

    protected:
      static void _bind_methods();

    public:
      GDExample();
      ~GDExample();

      void _process(double delta);
      void set_address(String str);
  };
}

#endif
