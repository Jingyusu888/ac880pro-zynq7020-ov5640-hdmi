from pathlib import Path
import json
p=Path(__file__).parent
rows=[l.split() for l in (p/'serializer_stream.txt').read_text().splitlines()]
loads=[r[2] for r in rows if r[0]=='L']; actual=''.join(r[2] for r in rows if r[0]=='S')
expected=''.join(s[::-1] for s in loads)[150:750]
hits=[i for i in range(len(actual)-len(expected)+1) if actual[i:i+len(expected)]==expected]
assert len(expected)==600 and len(hits)==1
rows=[l.split() for l in (p/'hdmi_link_stream.txt').read_text().splitlines()]
loads=[r for r in rows if r[0]=='L']; samples=[r for r in rows if r[0]=='S']; offsets=[]
for c,name in enumerate(['red','green','blue']):
 expected=''.join(r[2+c][::-1] for r in loads)[300:45300]
 actual=''.join(r[2+c] for r in samples)
 pos=actual.find(expected)
 assert len(expected)==45000 and pos>=0,name
 offsets.append(pos)
assert len(set(offsets))==1
clock=''.join(r[5] for r in samples); pattern=clock[:10]
assert pattern.count('1')==5 and pattern.count('0')==5
assert all(v==pattern[i%10] for i,v in enumerate(clock))
print('PASS: 600 standalone serial bits; 45000 bits/channel integrated; channel alignment; clock pattern.')
