from pathlib import Path
import xml.etree.ElementTree as ET,json
R=Path(__file__).resolve().parents[1]
# 引脚核对：依据厂商原理图手工转录，版权归原厂。
groups={
 'ddr3_dq': 'G21 H20 G20 F22 H19 F19 F21 G22 D21 E21 B20 C22 B21 B22 C20 D22',
 'ddr3_addr': 'F17 C18 F18 G17 D17 F16 D18 G15 D16 E16 A16 C19 B16 E18',
 'ddr3_ba':'G16 C17 A17', 'ddr3_dm':'H22 D20',
 'ddr3_dqs_p':'E19 A21','ddr3_dqs_n':'E20 A22',
 'ddr3_ck_p':'E15','ddr3_ck_n':'D15','ddr3_cke':'B15',
 'ddr3_cs_n':'H17','ddr3_odt':'C15'}
expected={f'{n}[{i}]':p for n,ps in groups.items() for i,p in enumerate(ps.split())}
expected.update(ddr3_ras_n='A19',ddr3_cas_n='A18',ddr3_we_n='B17',ddr3_reset_n='H18')
cfg=R/'camera_live/ip/mig_7series_0/mig_camera.prj'
c=ET.parse(cfg).getroot().find('Controller')
pins={p.get('name'):p for p in c.find('PinSelection')}
for n,p in expected.items():
 assert pins[n].get('PADName')==p,(n,p,pins[n].get('PADName'))
 assert '135' in pins[n].get('IOSTANDARD'),(n,'incorrect voltage standard')
assert c.findtext('MemoryVoltage')=='1.35V'
report=dict(result='PASS',ddr_pins_checked=len(expected),bank=35,
 schematic='vendor schematic (details omitted)',
 memory_voltage='1.35V',template=c.findtext('MemoryDevice'),
 note='Physical -125 part uses the built-in -15E DDR3L template at 400 MHz; board calibration remains untested.')
(R/'verification/camera_complete/board_pins.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
