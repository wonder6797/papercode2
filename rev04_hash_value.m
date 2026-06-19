function hex = rev04_hash_value(value)
%REV04_HASH_VALUE Stable SHA-256 for MATLAB values used in cache/resume keys.
bytes = getByteStreamFromArray(value);
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(bytes);
digest = typecast(md.digest(),'uint8');
hex = lower(string(reshape(dec2hex(digest,2).',1,[])));
end
