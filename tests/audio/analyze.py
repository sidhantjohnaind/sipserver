import json, math, wave, os
from pathlib import Path
import numpy as np

root = Path(os.environ.get('TEST_RESULTS', '/results'))

def read(path):
    with wave.open(str(path),'rb') as w:
        assert w.getframerate()==8000 and w.getsampwidth()==2 and w.getnchannels()==1
        return np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(float)/32768

def db(value):
    return float(20*np.log10(max(value,1e-12)))

def evaluate(folder):
    meta=json.loads((folder/'capture.json').read_text())
    x=read(folder/'g711_reference.wav')
    y=read(folder/'output.wav')
    nfft=1 << (len(x)+len(y)-2).bit_length()
    corr=np.fft.irfft(np.fft.rfft(y,nfft)*np.fft.rfft(x[::-1],nfft),nfft)[:len(x)+len(y)-1]
    lag=int(np.argmax(corr))-(len(x)-1)
    # Align by sample delay while retaining the original input timeline.
    x_start=max(0,-lag); y_start=max(0,lag)
    length=min(len(x)-x_start,len(y)-y_start)
    xa=x[x_start:x_start+length]; ya=y[y_start:y_start+length]
    timeline=(np.arange(length)+x_start)/8000
    voiced=(timeline>=1)&(timeline<len(x)/8000-1)
    xv=xa[voiced]; yv=ya[voiced]
    gain=float(np.dot(xv,yv)/np.dot(xv,xv))
    reference_rms=float(np.sqrt(np.mean(xv*xv)))
    residual= yv-gain*xv
    snr=float(10*np.log10(np.mean((gain*xv)**2)/max(1e-24,np.mean(residual**2))))
    silence=(timeline>.2)&(timeline<.8)
    silent_rms=float(np.sqrt(np.mean(ya[silence]**2)))
    segments={}
    for label,start,end in [('tone_1000_hz',1.15,2.85),('multitone',3.15,4.85),('voiced_harmonics',5.15,6.85),('speech',7.0,len(x)/8000-1)]:
        mask=(timeline>=start)&(timeline<end)
        a,b=xa[mask],ya[mask]
        if len(a)<2 or np.dot(a,a)==0:
            segments[label]=dict(gain=None,correlation=None,snr_db=None)
            continue
        g=float(np.dot(a,b)/max(1e-24,np.dot(a,a)))
        segments[label]=dict(gain=g,correlation=float(np.corrcoef(a,b)[0,1]),
                            snr_db=float(10*np.log10(max(1e-24,np.mean((g*a)**2))/max(1e-24,np.mean((b-g*a)**2)))))
    metrics=dict(**meta,alignment_delay_ms=lag/8,reference_rms_dbfs=db(reference_rms),
                 output_gain=gain,output_gain_db=db(abs(gain)),
                 correlation=float(np.corrcoef(xv,yv)[0,1]),gain_adjusted_snr_db=snr,
                 output_silence_rms_dbfs=db(silent_rms),clipped_samples=int(np.sum(np.abs(y)>=32760/32768)),
                 decoded_output_samples=len(y),segments=segments)
    wav=folder/'aligned-output.wav'
    with wave.open(str(wav),'wb') as w:
        w.setparams((1,2,8000,0,'NONE','not compressed'))
        w.writeframes((np.clip(ya,-1,1)*32767).astype('<i2').tobytes())
    (folder/'metrics.json').write_text(json.dumps(metrics,indent=2))
    return metrics

results=[evaluate(folder) for folder in sorted(root.iterdir()) if (folder/'capture.json').exists()]
(root/'summary.json').write_text(json.dumps(results,indent=2))
print(json.dumps(results,indent=2))
