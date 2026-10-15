#!/usr/bin/env python3
"""Run the real headless runtime against an isolated gel endpoint or native firmware."""
import argparse,json,os,pathlib,socket,subprocess,tempfile,threading,time,select
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=pathlib.Path,required=True,help='JSON evidence file; synthetic input only')
parser.add_argument('--native',action='store_true',help='use the real gel firmware simulator instead of a synthetic endpoint')
args=parser.parse_args();root=pathlib.Path(__file__).resolve().parents[4]
with tempfile.TemporaryDirectory(prefix='boop-gel-',dir='/tmp') as folder:
    base=pathlib.Path(folder);state=base/'state';state.mkdir();home=base/'home';home.mkdir()
    (state/'settings.json').write_text(json.dumps({'moodGraph':'v3'}))
    path=str(base/'link');server=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);server.bind(path);server.listen(1);server.settimeout(10)
    captured=[];native_messages=[];errors=[];done=threading.Event()
    def native_peer():
        sim_env=os.environ.copy();sim_env['BOOP_SIM_FACE']='gel'
        sim=subprocess.Popen([str(root/'firmware/.pio/build/native/program')],cwd=root,env=sim_env,
                             stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        def write(message):
            sim.stdin.write((json.dumps(message)+'\n').encode());sim.stdin.flush()
        try:
            conn,_=server.accept()
            with conn:
                write({'t':'hello'});incoming=b'';outgoing=b'';next_tick=time.monotonic()
                while not done.is_set():
                    ready,_,_=select.select([conn,sim.stdout],[],[],.005)
                    if conn in ready:
                        chunk=conn.recv(8192)
                        if not chunk:break
                        incoming+=chunk
                        while b'\n' in incoming:
                            line,incoming=incoming.split(b'\n',1);message=json.loads(line);captured.append(message);write(message)
                            if message.get('t')=='state':write({'t':'dbg.state'})
                    if sim.stdout in ready:
                        chunk=os.read(sim.stdout.fileno(),65536)
                        if not chunk:raise RuntimeError('native simulator exited')
                        outgoing+=chunk
                        while b'\n' in outgoing:
                            line,outgoing=outgoing.split(b'\n',1);message=json.loads(line)
                            if message.get('t')!='dbg.clock':native_messages.append(message)
                            if not message.get('t','').startswith('dbg.'):conn.sendall(line+b'\n')
                    if time.monotonic()>=next_tick:
                        write({'t':'dbg.clock','step':16});next_tick=time.monotonic()+.016
        except Exception as error:errors.append(str(error))
        finally:
            sim.stdin.close()
            try:sim.wait(timeout=3)
            except subprocess.TimeoutExpired:sim.kill();sim.wait()
            if sim.returncode:errors.append('simulator: '+sim.stderr.read().decode())
    def peer():
        if args.native:return native_peer()
        try:
            conn,_=server.accept()
            with conn:
                conn.settimeout(.2)
                hello={'t':'hello','kit':1,'app':'boop','id':'gel-fixture','fw':'synthetic','face':'gel','voice':'none',
                       'does':['react','starting','task_complete','reply_ready','poked','tap_spam','listening','stop_listening','error','stopped','helper_return']}
                conn.sendall((json.dumps(hello)+'\n').encode());buffer=b''
                while not done.is_set():
                    try:chunk=conn.recv(8192)
                    except socket.timeout:continue
                    if not chunk:break
                    buffer+=chunk
                    while b'\n' in buffer:
                        line,buffer=buffer.split(b'\n',1)
                        message=json.loads(line);captured.append(message)
                        if message.get('t')=='hello':conn.sendall((json.dumps(hello)+'\n').encode())
                        if message.get('t')=='do':conn.sendall((json.dumps({'t':'ev','kind':'ended','data':{'id':message['id'],'how':'done'}})+'\n').encode())
        except Exception as e:errors.append(str(e))
    worker=threading.Thread(target=peer);worker.start()
    env=os.environ.copy();env['HOME']=str(home);env.pop('BOOP_JEV_KEY',None)
    log=base/'headless.log'
    with log.open('w') as output:
        process=subprocess.Popen([str(root/'.build/debug/Boop'),'--headless','--state-dir',str(state),'--brain','scripted',
                                  '--link','usb:'+path,'--debug','--no-open'],cwd=root,env=env,stdout=output,stderr=subprocess.STDOUT)
        def wait(predicate):
            deadline=time.monotonic()+10
            while time.monotonic()<deadline:
                if predicate():return
                if process.poll() is not None:raise RuntimeError(log.read_text())
                time.sleep(.02)
            raise RuntimeError('Timed out: '+log.read_text())
        def send(message):
            with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as sock:
                sock.connect(str(state/'boop.sock'));sock.sendall((json.dumps(message)+'\n').encode())
        def hook(name,**extra):send({'agent':'claude','hook':name,'session':'slime-fixture','cwd':'/tmp/slime-fixture',
                                    'ts':int(time.time()*1000),**extra})
        try:
            wait(lambda:(state/'boop.sock').exists() and any(m.get('t')=='state' for m in captured))
            hook('UserPromptSubmit',prompt='Render the synthetic fixture.')
            wait(lambda:any(m.get('base')=='working' for m in captured))
            hook('PreToolUse',tool='Bash',tool_use_id='fixture-tool')
            wait(lambda:any(m.get('act')=='terminal' for m in captured))
            send({'dev':'mood','mood':'frightened'})
            wait(lambda:any(m.get('mood')=='frightened' for m in captured))
            hook('PermissionRequest',tool='Bash',tool_use_id='fixture-tool')
            wait(lambda:any('attn' in m for m in captured))
            send({'dev':'mood','mood':'happy'})
            wait(lambda:any('attn' in m and m.get('mood')=='happy' for m in captured))
            assert any(m.get('t')=='do' for m in captured)
            if args.native:
                wait(lambda:any(m.get('t')=='dbg.state' and m.get('mood')=='happy' and m.get('attn') for m in native_messages))
                assert any(m.get('t')=='hello' and m.get('face')=='gel' for m in native_messages)
                assert any(m.get('t')=='dbg.state' and m.get('mood')=='frightened' for m in native_messages)
                wait(lambda:any(m.get('t')=='ev' and m.get('kind')=='ended' for m in native_messages))
        finally:
            process.terminate();process.wait(timeout=10);done.set();worker.join(timeout=2);server.close()
        assert not errors,errors
        assert process.returncode==0,log.read_text()
        evidence={'status':'HEADLESS NATIVE GEL PASS' if args.native else 'HEADLESS GEL MIRROR INPUT PASS','endpoint':'native gel simulator via Unix socket' if args.native else 'synthetic Unix socket; no board or Bluetooth',
                  'brain':'scripted; no API key','messages':captured,'nativeMessages':native_messages}
        args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(evidence,indent=2)+'\n')
        print(evidence['status']+': '+str(len(captured))+' real outgoing messages')
