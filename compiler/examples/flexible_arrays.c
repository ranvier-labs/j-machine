struct Packet {
  int length;
  int payload[];
};

int backing[6];

int checksum(struct Packet *packet) {
  int total = 0;
  for (int index = 0; index < packet->length; ++index) {
    total += packet->payload[index];
  }
  return total;
}

int main(void) {
  struct Packet header = {2};
  struct Packet copy = header;
  struct Packet *packet = (struct Packet *)backing;

  packet->length = 5;
  packet->payload[0] = 3;
  packet->payload[1] = 5;
  packet->payload[2] = 7;
  packet->payload[3] = 11;
  packet->payload[4] = 13;

  copy.length += packet->length;
  return sizeof(struct Packet) + checksum(packet)
      + (packet->payload - backing) + copy.length;
}
