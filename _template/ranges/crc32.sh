set -- __ranges

echo __clusterdir/sql.sh "'select conv(bit_xor(cast(crc32(concat("__columns")) as unsigned)), 10, 16) from __schema.__table where __pk between $1 and ${@:$#}'"
