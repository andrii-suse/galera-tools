set -- __ranges
echo "select __pk, conv(bit_xor(cast(crc32(concat("__columns")) as unsigned)), 10, 16) from "__schema.__table" where __pk in(INCONDITION) group by __pk"
