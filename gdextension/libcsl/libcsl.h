typedef void Address;

extern "C" {

const Address *new_address_from_bech32(const char *addr_bech32);
void free_address(const Address *address);
const char *address_to_hex(const Address *address);
void free_string(const Address *address);

} // extern "C"
