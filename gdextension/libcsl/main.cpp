#include <iostream>

#include "libcsl.h"

const char *address_bech32 = "addr1x8nz307k3sr60gu0e47cmajssy4fmld7u493a4xztjrll0aj764lvrxdayh2ux30fl0ktuh27csgmpevdu89jlxppvrswgxsta";

int main() {
    const Address *address = new_address_from_bech32(address_bech32);
    const char *address_hex = address_to_hex(address);
    printf("%p: %s\n", address, address_hex);
    free_address(address);
    free_string(address_hex);
}
