import json, math, os, re, select, socket, ssl, struct, subprocess, threading, time, uuid, wave
from pathlib import Path

ROOT = Path(os.environ.get('TEST_ROOT', '/test'))
RATE = 8000
CODECS = {
    'PCMA': dict(pt=8, pcm_rate=8000, rtp_rate=8000, format='alaw'),
    'PCMU': dict(pt=0, pcm_rate=8000, rtp_rate=8000, format='mulaw'),
    'AMR': dict(pt=97, pcm_rate=8000, rtp_rate=8000),
    # RFC 3551: 16 kHz audio but an 8 kHz RTP clock for G.722.
    'G722': dict(pt=9, pcm_rate=16000, rtp_rate=8000, format='g722'),
    'AMR-WB': dict(pt=98, pcm_rate=16000, rtp_rate=16000),
}
G711_SDP_PTIME = int(os.environ.get('TEST_SDP_PTIME', '20'))
STOP = threading.Event()

def wav_write(path, samples):
    with wave.open(str(path), 'wb') as w:
        w.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        w.writeframes(struct.pack('<%dh' % len(samples), *samples))

def source_signal():
    out = []
    for n in range(8 * RATE):
        t = n / RATE
        if 1 <= t < 3:
            x = .25 * math.sin(2 * math.pi * 1000 * t)
        elif 3 <= t < 5:
            frequencies = (300, 700, 5000) if RATE == 16000 else (300, 700, 1300)
            x = sum(.075 * math.sin(2 * math.pi * f * t) for f in frequencies)
        elif 5 <= t < 7:
            # Deterministic voiced harmonic signal, not a speech-quality/MOS test.
            fundamental = 125
            env = .5 + .5 * math.sin(2 * math.pi * 3 * t)
            x = env * sum(.15 / k * math.sin(2 * math.pi * fundamental * k * t)
                          for k in range(1, 13))
        else:
            x = 0
        out.append(round(32767 * x))
    speech = ROOT/'reference-speech.wav'
    if speech.exists():
        with wave.open(str(speech),'rb') as w:
            assert w.getframerate()==RATE and w.getsampwidth()==2 and w.getnchannels()==1
            pcm = w.readframes(w.getnframes())
            values = list(struct.unpack('<%dh' % (len(pcm)//2),pcm))
        peak=max(abs(v) for v in values) or 1
        values=[round(v*8192/peak) for v in values]
        out=out[:7*RATE]+values+out[7*RATE:]
    out += [0] * ((-len(out)) % (RATE//50))
    return out

def headers(msg):
    lines = msg.split('\r\n')
    h = {}
    for line in lines[1:]:
        if ':' in line:
            k, v = line.split(':', 1)
            h[k.lower()] = v.strip()
    return h

def response(msg, code=200, body='', contact='sip:fake@127.0.0.1:15068;transport=tls'):
    h = headers(msg)
    to = h['to']
    if 'tag=' not in to:
        to += ';tag=test-server'
    lines = [f'SIP/2.0 {code} OK', 'Via: ' + h['via'], 'From: ' + h['from'],
             'To: ' + to, 'Call-ID: ' + h['call-id'], 'CSeq: ' + h['cseq'],
             f'Contact: <{contact}>', 'Allow: INVITE, ACK, BYE, CANCEL, OPTIONS, REGISTER',
             'Expires: 3600']
    if body:
        lines += ['Content-Type: application/sdp']
    return '\r\n'.join(lines + [f'Content-Length: {len(body.encode())}', '', body]).encode()

def sdp(codec, port, pt=None):
    info = CODECS[codec]
    pt = info['pt'] if pt is None else pt
    lines = ['v=0', 'o=test 1 1 IN IP4 127.0.0.1', 's=converter-test',
             'c=IN IP4 127.0.0.1', 't=0 0', f'm=audio {port} RTP/AVP {pt}',
             f"a=rtpmap:{pt} {codec}/{info['rtp_rate']}",
             f'a=ptime:{G711_SDP_PTIME if codec in ("PCMA","PCMU") else 20}', 'a=sendrecv']
    if codec in ('AMR', 'AMR-WB'):
        mode = 7 if codec == 'AMR' else 2
        lines += [f'a=fmtp:{pt} octet-align=1;mode-set={mode}']
    return '\r\n'.join(lines) + '\r\n'

class FakeCarrier:
    def __init__(self, codec):
        self.codec = codec
        self.pt = None
        self.offer_sdp = None
        self.registered = threading.Event()
        self.answered = threading.Event()
        self.messages = []
        self.errors = []
        self.sock = socket.socket()
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(('127.0.0.1', 15068))
        self.sock.listen()
        self.sock.settimeout(.2)
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(str(ROOT/'cert.pem'), str(ROOT/'key.pem'))
        while not STOP.is_set():
            try:
                conn, _ = self.sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            try:
                with context.wrap_socket(conn, server_side=True) as tls:
                    tls.settimeout(.2)
                    buf = b''
                    while not STOP.is_set():
                        try:
                            chunk = tls.recv(65536)
                        except socket.timeout:
                            continue
                        if not chunk:
                            break
                        buf += chunk
                        while True:
                            buf = buf.lstrip(b'\r\n')
                            end = buf.find(b'\r\n\r\n')
                            if end < 0:
                                break
                            head = buf[:end].decode(errors='replace')
                            length = int(headers(head).get('content-length', '0'))
                            if len(buf) < end + 4 + length:
                                break
                            msg = buf[:end+4+length].decode(errors='replace')
                            buf = buf[end+4+length:]
                            first = msg.split('\r\n')[0]
                            self.messages.append(first)
                            if first.startswith('REGISTER'):
                                tls.sendall(response(msg))
                                self.registered.set()
                            elif first.startswith('INVITE'):
                                self.offer_sdp = msg.split('\r\n\r\n',1)[1]
                                match = re.search(r'a=rtpmap:(\d+) '+re.escape(self.codec)+
                                                  r'/'+str(CODECS[self.codec]['rtp_rate'])+r'(?:[/\s]|$)',
                                                  self.offer_sdp)
                                if not match:
                                    raise RuntimeError(f'{self.codec} not offered by bridge')
                                self.pt = int(match.group(1))
                                tls.sendall(response(msg, body=sdp(self.codec, 16000, self.pt)))
                            elif first.startswith('ACK'):
                                self.answered.set()
                            elif first.startswith(('BYE', 'OPTIONS', 'CANCEL')):
                                tls.sendall(response(msg))
            except Exception as e:
                self.errors.append(str(e))

    def close(self):
        self.sock.close()
        self.thread.join(2)

def rtp_payload(packet):
    if len(packet) < 12 or packet[0] >> 6 != 2:
        return None
    off = 12 + (packet[0] & 15) * 4
    if packet[0] & 16:
        off += 4 + 4 * struct.unpack('!H', packet[off+2:off+4])[0]
    end = len(packet) - packet[-1] if packet[0] & 32 else len(packet)
    return (struct.unpack('!H', packet[2:4])[0], struct.unpack('!I', packet[4:8])[0],
            packet[1] & 127, packet[off:end])

AMR_LENGTHS = [12, 13, 15, 17, 19, 20, 26, 31, 5, 0, 0, 0, 0, 0, 0, 0]
AMRWB_LENGTHS = [17, 23, 32, 36, 40, 46, 50, 58, 60, 5, 0, 0, 0, 0, 0, 0]

def raw_decode_args(codec):
    info = CODECS[codec]
    args = ['-f', info['format']]
    if codec in ('PCMA', 'PCMU'):
        args += ['-ar', str(info['pcm_rate']), '-ac', '1']
    return args

def encode_amrwb(samples):
    """Generate valid source frames directly with VisualOn, outside the bridge."""
    import ctypes as c
    lib = c.CDLL('libvo-amrwbenc.so.0')
    lib.E_IF_init.restype = c.c_void_p
    lib.E_IF_encode.argtypes = [c.c_void_p, c.c_int, c.POINTER(c.c_short),
                               c.POINTER(c.c_ubyte), c.c_int]
    lib.E_IF_encode.restype = c.c_int
    lib.E_IF_exit.argtypes = [c.c_void_p]
    state = lib.E_IF_init()
    if not state:
        raise RuntimeError('AMR-WB source encoder initialization failed')
    data = bytearray(b'#!AMR-WB\n')
    try:
        for i in range(0,len(samples),320):
            pcm = (c.c_short*320)(*samples[i:i+320])
            encoded = (c.c_ubyte*64)()
            size = lib.E_IF_encode(state,2,pcm,encoded,0)
            assert size == 33
            data.extend(bytes(encoded[:size]))
    finally:
        lib.E_IF_exit(state)
    return bytes(data)


def decode_capture(folder, packets, codec):
    packets.sort(key=lambda p:p[1])
    if codec in ('AMR', 'AMR-WB'):
        lengths = AMR_LENGTHS if codec == 'AMR' else AMRWB_LENGTHS
        sid_type = 8 if codec == 'AMR' else 9
        data = bytearray(b'#!AMR\n' if codec == 'AMR' else b'#!AMR-WB\n')
        frame_types = {}
        for seq, ts, pt, payload in packets:
            if len(payload) < 2:
                continue
            toc, offset = [], 1
            while offset < len(payload):
                b = payload[offset]
                toc.append(b)
                offset += 1
                if not b & 128:
                    break
            for b in toc:
                ft = (b >> 3) & 15
                size = lengths[ft]
                valid_fts = (*range(sid_type+1),15) if codec == 'AMR' else (*range(sid_type+1),14,15)
                if ft not in valid_fts or offset+size > len(payload):
                    raise ValueError(f'Invalid AMR frame ft={ft}, payload={len(payload)}, offset={offset}')
                frame_types[str(ft)] = frame_types.get(str(ft), 0) + 1
                data.append(b & 124)
                data += payload[offset:offset+size]
                offset += size
            if offset != len(payload):
                raise ValueError('AMR payload length did not match TOC')
        path = folder/('captured.amr' if codec == 'AMR' else 'captured.amrwb')
        path.write_bytes(data)
        cmd = ['ffmpeg','-v','error','-y','-i',str(path),'-ar',str(CODECS[codec]['pcm_rate']),'-ac','1',str(folder/'output.wav')]
    else:
        path = folder/('captured.'+CODECS[codec]['format'])
        path.write_bytes(b''.join(p[3] for p in packets))
        frame_types = {}
        cmd = ['ffmpeg','-v','error','-y']+raw_decode_args(codec)+['-i',str(path),str(folder/'output.wav')]
    result = subprocess.run(cmd,capture_output=True,text=True)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return frame_types, result.stderr

def run_case(local_codec, carrier_codec, packet_samples=None):
    global RATE
    RATE = CODECS[local_codec]['pcm_rate']
    packet_samples = RATE//50 if packet_samples is None else packet_samples
    STOP.clear()
    name = local_codec.lower() + '_to_' + carrier_codec.lower()
    if packet_samples != RATE//50:
        name += f'_{packet_samples*1000//RATE}ms_input'
    if G711_SDP_PTIME != 20:
        name += f'_sdp{G711_SDP_PTIME}'
    folder = ROOT/name
    folder.mkdir(exist_ok=True)
    signal = source_signal()
    wav_write(folder/'input.wav', signal)
    if local_codec in ('AMR', 'AMR-WB'):
        if local_codec == 'AMR':
            # Reuse a validated narrowband capture for the optional reverse test.
            raw_path = ROOT/'pcma_to_amr'/'captured.amr'
            data = raw_path.read_bytes()
            assert data.startswith(b'#!AMR\n')
            offset, lengths = 6, AMR_LENGTHS
        else:
            data = encode_amrwb(signal)
            raw_path = folder/'input.amrwb'
            raw_path.write_bytes(data)
            offset, lengths = 9, AMRWB_LENGTHS
        chunks = []
        while offset < len(data):
            toc = data[offset]
            ft = (toc >> 3) & 15
            size = lengths[ft]
            assert ft <= (8 if local_codec == 'AMR' else 9) and offset+1+size <= len(data)
            chunks.append(bytes([0xf0, toc & 124])+data[offset+1:offset+1+size])
            offset += 1+size
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(raw_path),
                        '-ar',str(RATE),'-ac','1',str(folder/'g711_reference.wav')],check=True)
    else:
        fmt = CODECS[local_codec]['format']
        raw_path = folder/('input.'+fmt)
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(folder/'input.wav'),'-f',fmt,str(raw_path)],check=True)
        subprocess.run(['ffmpeg','-v','error','-y']+raw_decode_args(local_codec)+['-i',str(raw_path),str(folder/'g711_reference.wav')],check=True)
        raw = raw_path.read_bytes()
        # G.722 encodes two PCM samples per byte at 64 kbps.
        packet_bytes = packet_samples//2 if local_codec == 'G722' else packet_samples
        chunks = [raw[i:i+packet_bytes] for i in range(0,len(raw),packet_bytes)]
    carrier = FakeCarrier(carrier_codec)
    env = dict(os.environ, PUBLIC_ID='sip:100@test.invalid', SIP_AUTH_USER='100@test.invalid',
               SIP_PASSWORD='test-only', SIP_REALM='test.invalid', PROXY_HOST='127.0.0.1',
               PROXY_PORT='15068', LOCAL_PORT='15061', DNS_SERVERS='127.0.0.1',
               LOG_LEVEL='3', LOG_FILE='0', KEEPALIVE='3600',
               DEST_TO_UPSTREAM_TMPL='sip:{user}@test.invalid')
    log = open(folder/'bridge.log','w')
    proc = subprocess.Popen([os.environ.get('TEST_BINARY', '/usr/local/bin/b2bua')],env=env,stdout=log,stderr=subprocess.STDOUT,cwd=folder)
    udp = socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    udp.bind(('127.0.0.1',15060))
    udp.settimeout(10)
    recv = socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    recv.bind(('127.0.0.1',16000))
    recv.settimeout(.1)
    local_rtp = socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    local_rtp.bind(('127.0.0.1',16002))
    packets = []
    capture_stop = threading.Event()
    def collect():
        while not capture_stop.is_set():
            try:
                value = rtp_payload(recv.recv(65536))
                if value:
                    packets.append(value)
            except socket.timeout:
                pass
    thread = threading.Thread(target=collect,daemon=True)
    try:
        if not carrier.registered.wait(15):
            raise RuntimeError('Isolated bridge did not register to fake carrier')
        # The carrier's reply precedes the bridge's registration callback.
        deadline = time.monotonic()+5
        while 'SUCCESS: Registered with Jio IMS!' not in (folder/'bridge.log').read_text(errors='replace'):
            if time.monotonic()>deadline or proc.poll() is not None:
                raise RuntimeError('Bridge did not confirm synthetic registration')
            time.sleep(.02)
        body = sdp(local_codec,16002)
        cid = uuid.uuid4().hex
        uri = 'sip:12345@127.0.0.1:15061'
        lines = [f'INVITE {uri} SIP/2.0',f'Via: SIP/2.0/UDP 127.0.0.1:15060;branch=z9hG4bK{cid};rport',
                 'Max-Forwards: 70',f'From: <sip:100@127.0.0.1>;tag={cid}',f'To: <{uri}>',
                 f'Call-ID: {cid}','CSeq: 1 INVITE','Contact: <sip:100@127.0.0.1:15060>',
                 'Content-Type: application/sdp',f'Content-Length: {len(body)}','','']
        udp.sendto(('\r\n'.join(lines)+body).encode(),('127.0.0.1',15061))
        responses = []
        while True:
            msg = udp.recv(65536).decode(errors='replace')
            responses.append(msg.split('\r\n')[0])
            if msg.startswith('SIP/2.0 200'):
                break
            if re.match(r'SIP/2.0 [456]',msg):
                raise RuntimeError(msg)
        h = headers(msg.split('\r\n\r\n')[0])
        contact = re.search(r'<([^>]+)>',h['contact']).group(1)
        ack = [f'ACK {contact} SIP/2.0',f'Via: SIP/2.0/UDP 127.0.0.1:15060;branch=z9hG4bKack{cid}',
               'Max-Forwards: 70','From: '+h['from'],'To: '+h['to'],'Call-ID: '+cid,
               'CSeq: 1 ACK','Content-Length: 0','','']
        udp.sendto('\r\n'.join(ack).encode(),('127.0.0.1',15061))
        local_sdp = msg.split('\r\n\r\n',1)[1]
        (folder/'local_answer.sdp').write_text(local_sdp)
        dest_port = int(re.search(r'm=audio (\d+)',local_sdp).group(1))
        if not carrier.answered.wait(5):
            raise RuntimeError('Fake carrier did not receive ACK')
        (folder/'upstream_offer.sdp').write_text(carrier.offer_sdp)
        thread.start()
        time.sleep(.3)
        start = time.monotonic()
        seq, timestamp, pt = 1000, 160000, CODECS[local_codec]['pt']
        rtp_step = packet_samples*CODECS[local_codec]['rtp_rate']//RATE
        # Packet pacing uses PCM time; RTP timestamps use the codec RTP clock.
        for chunk_index, chunk in enumerate(chunks):
            due = start + chunk_index*packet_samples/RATE
            delay = due-time.monotonic()
            if delay>0:
                time.sleep(delay)
            packet = struct.pack('!BBHII',0x80,pt,seq,timestamp,0x12345678)+chunk
            local_rtp.sendto(packet,('127.0.0.1',dest_port))
            seq=(seq+1)&65535
            timestamp+=rtp_step
            # Drain bridge-to-softphone audio, so the receive socket never overflows.
            local_rtp.setblocking(False)
            try:
                while local_rtp.recv(65536):
                    pass
            except BlockingIOError:
                pass
        elapsed = time.monotonic()-start
        time.sleep(.5)
        bye = [f'BYE {contact} SIP/2.0',f'Via: SIP/2.0/UDP 127.0.0.1:15060;branch=z9hG4bKbye{cid}',
               'Max-Forwards: 70','From: '+h['from'],'To: '+h['to'],'Call-ID: '+cid,
               'CSeq: 2 BYE','Content-Length: 0','','']
        udp.sendto('\r\n'.join(bye).encode(),('127.0.0.1',15061))
        time.sleep(.3)
        capture_stop.set()
        thread.join(1)
        if not packets:
            raise RuntimeError('No RTP output received')
        frames, decoder_errors = decode_capture(folder,packets,carrier_codec)
        seqs = sorted(set(p[0] for p in packets))
        metadata=dict(case=name,local_codec=local_codec,carrier_codec=carrier_codec,
                      input_packet_duration_ms=packet_samples*1000/RATE,
                      input_pcm_rate=RATE, output_pcm_rate=CODECS[carrier_codec]['pcm_rate'],
                      input_rtp_clock=CODECS[local_codec]['rtp_rate'],
                      output_rtp_clock=CODECS[carrier_codec]['rtp_rate'],
                      offered_carrier_payload_type=carrier.pt,
                      captured_payload_types=sorted(set(p[2] for p in packets)),
                      g711_sdp_ptime_ms=G711_SDP_PTIME,
                      sent_packets=len(chunks),send_elapsed_seconds=elapsed,
                      input_payload_lengths=sorted(set(len(chunk) for chunk in chunks)),
                      received_packets=len(packets),sequence_gaps=sum(max(0,b-a-1) for a,b in zip(seqs,seqs[1:])),
                      rtp_timestamp_steps=sorted(set(b[1]-a[1] for a,b in zip(packets,packets[1:]))),
                      rtp_payload_lengths=sorted(set(len(p[3]) for p in packets)),
                      amr_frame_types=frames,ffmpeg_decoder_errors=decoder_errors,
                      sip_responses=responses,carrier_errors=carrier.errors)
        (folder/'capture.json').write_text(json.dumps(metadata,indent=2))
        print(json.dumps(metadata),flush=True)
    finally:
        capture_stop.set()
        proc.terminate()
        try:
            proc.wait(5)
        except subprocess.TimeoutExpired:
            proc.kill();proc.wait()
        log.close()
        STOP.set()
        carrier.close()
        for sock in (udp,recv,local_rtp):
            sock.close()

if __name__=='__main__':
    for case in [('PCMA','PCMA',160),('PCMA','AMR',160),('PCMU','AMR',160),
                 ('PCMA','PCMA',80),('PCMA','AMR',80)]:
        run_case(*case)
    G711_SDP_PTIME = 10
    for case in [('PCMA','PCMA',80),('PCMA','AMR',80)]:
        run_case(*case)
