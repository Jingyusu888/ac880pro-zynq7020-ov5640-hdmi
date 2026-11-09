from pathlib import Path
import subprocess,json
p=Path(r'D:\Electronic_hardware\FPGA\project\cam_yolo')
a=p/'verification/audit_20261108'
b=Path(r'E:\vivado\Xilinx\Vivado\2018.3\bin')
def run(tool,args,log):
 r=subprocess.run([str(b/(tool+'.bat'))]+[str(x) for x in args],cwd=a,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 s=r.stdout.decode('utf-8',errors='replace');(a/log).write_text(s,encoding='utf-8')
 if r.returncode or 'Fatal:' in s or 'ERROR:' in s: raise RuntimeError(log+'\n'+s[-2200:])
 return s
src=p/'cam_yolo.srcs/sources_1/new';tb=p/'cam_yolo.srcs/sim_1/new'
files=[src/(n+'.v') for n in ['video_timing','color_bar','tmds_encoder','tmds_encode_rgb','serializer_10to1','dvi_tx','video_source','video_clock_reset','hdmi_test_top']]
files += [tb/(n+'.v') for n in ['tb_video_timing','tb_color_bar','tb_tmds_encoder','tb_tmds_encode_rgb','tb_serializer_10to1']]
files += [Path(r'E:\vivado\Xilinx\Vivado\2018.3\data\verilog\src\glbl.v')]
run('xvlog',files,'compile.log')
results={}
for top in ['tb_video_timing','tb_color_bar','tb_tmds_encoder','tb_tmds_encode_rgb']:
 run('xelab',['-L','unisims_ver','-L','secureip',top,'glbl','-s',top+'_audit','-mt','2'],top+'_elab.log')
 s=run('xsim',[top+'_audit','-runall','-log',top+'_runtime.log'],top+'_run.log')
 results[top]=[l for l in s.splitlines() if any(k in l for k in ['PASS:','Frame 1:','completed','Fatal:'])]
 print(top,results[top],flush=True)
(a/'existing_tests.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
