"""Rebuild the ROM from the pinned local upstream snapshot; no network access."""
from pathlib import Path
import hashlib
import json
import re

root=Path(__file__).resolve().parents[1]
vendor=root/'third_party/ov5640_af'
meta=json.loads((vendor/'upstream.json').read_text(encoding='utf-8'))
header=(vendor/'ov5640_af_firmware.h').read_bytes()
assert hashlib.sha256(header).hexdigest()==meta['header_sha256']
array=header.decode().split('ov5640_af_firmware[] = {',1)[1].split('}',1)[0]
data=bytes(int(x,16) for x in re.findall(r'0x([0-9a-fA-F]{2})',array))
assert len(data)==4077==meta['firmware_bytes']
assert hashlib.sha256(data).hexdigest()==meta['firmware_sha256']
rom=data+bytes(4096-len(data))
(root/'rtl/camera_af/ov5640_af_firmware.mem').write_text(
 ''.join(f'{byte:02x}\n' for byte in rom),encoding='ascii')
print('Verified pinned 4077-byte AF firmware; generated padded 4096-byte ROM.')
